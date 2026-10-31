import Foundation
import QuillCore

enum AgentEvent {
    case activity(String)
    case text(String)
    case proposed(String)
}

struct AgentError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

@MainActor
protocol Agent: AnyObject {
    var canEditFiles: Bool { get }
    func prepare(cwd: URL) async throws
    func send(_ prompt: String, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws
    func cancel()
}

struct AgentSpec: Identifiable, Hashable {
    enum Kind: Hashable { case acp(String), anthropic }
    var id: String
    var name: String
    var detail: String
    var kind: Kind
    var requires: String?

    static let all: [AgentSpec] = [
        AgentSpec(id: "claude", name: "Claude Code", detail: "Your Claude subscription, through Claude Code",
                  kind: .acp("npx -y @agentclientprotocol/claude-agent-acp@0.99.1"), requires: "claude"),
        AgentSpec(id: "anthropic", name: "Anthropic API", detail: "Claude Opus 5.5 with your API key",
                  kind: .anthropic, requires: nil),
        AgentSpec(id: "gemini", name: "Gemini CLI", detail: "Google's agent over ACP",
                  kind: .acp("gemini --experimental-acp"), requires: "gemini"),
        AgentSpec(id: "opencode", name: "OpenCode", detail: "Any model OpenCode is signed in to",
                  kind: .acp("opencode acp"), requires: "opencode"),
    ]

    static func named(_ id: String) -> AgentSpec { all.first { $0.id == id } ?? all[0] }

    @MainActor func make() -> Agent {
        switch kind {
        case .acp(let command): ACPAgent(command: command)
        case .anthropic: AnthropicAgent()
        }
    }
}

func loginShell(_ command: String) -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", command]
    return p
}

func installed(_ binary: String) async -> Bool {
    await withCheckedContinuation { done in
        let p = loginShell("command -v \(binary)")
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { done.resume(returning: $0.terminationStatus == 0) }
        do { try p.run() } catch { done.resume(returning: false) }
    }
}

private struct Message: @unchecked Sendable {
    var body: [String: Any]
}

@MainActor
final class ACPAgent: Agent {
    let command: String
    let canEditFiles = true
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var waiting: [Int: CheckedContinuation<Message, Error>] = [:]
    private var session: String?
    private var cwd: URL?
    private var starting: Task<Void, Error>?
    private var events: (@MainActor (AgentEvent) -> Void)?
    private let log: FileHandle?

    init(command: String) {
        self.command = command
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appending(path: "Logs/Quill")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "agent.log")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        log = try? FileHandle(forWritingTo: file)
        _ = try? log?.seekToEnd()
    }

    func prepare(cwd: URL) async throws {
        if session != nil, self.cwd == cwd { return }
        if let starting { return try await starting.value }
        let task = Task { try await self.boot(cwd: cwd) }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    private func boot(cwd: URL) async throws {
        if process == nil { try launch(cwd: cwd) }
        let initialized = try await request("initialize", [
            "protocolVersion": 1,
            "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": true], "terminal": false],
            "clientInfo": ["name": "Quill", "version": "0.1"],
        ])
        _ = initialized
        let created = try await request("session/new", ["cwd": cwd.path, "mcpServers": []])
        guard let id = created.body["sessionId"] as? String else { throw AgentError(message: "The agent didn't open a session.") }
        session = id
        self.cwd = cwd
    }

    private func launch(cwd: URL) throws {
        let p = loginShell("exec \(command)")
        p.currentDirectoryURL = cwd
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        let log = log
        stderr.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if !d.isEmpty { log?.write(d) }
        }
        stdout.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            Task { @MainActor in self?.ingest(d) }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.died() }
        }
        try p.run()
        process = p
        input = stdin.fileHandleForWriting
    }

    private func died() {
        process = nil
        input = nil
        session = nil
        for (_, c) in waiting { c.resume(throwing: AgentError(message: "The agent stopped. Check that it's installed and signed in.")) }
        waiting = [:]
    }

    func send(_ prompt: String, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws {
        guard let cwd else { throw AgentError(message: "The agent isn't ready yet.") }
        try await prepare(cwd: cwd)
        guard let session else { throw AgentError(message: "The agent isn't ready yet.") }
        self.events = events
        defer { self.events = nil }
        let result = try await request("session/prompt", ["sessionId": session, "prompt": [["type": "text", "text": prompt]]])
        if let reason = result.body["stopReason"] as? String, reason == "refusal" {
            throw AgentError(message: "The agent declined that one.")
        }
    }

    func cancel() {
        guard let session else { return }
        write(["jsonrpc": "2.0", "method": "session/cancel", "params": ["sessionId": session]])
    }

    private func request(_ method: String, _ params: [String: Any]) async throws -> Message {
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { c in
            waiting[id] = c
            write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        }
    }

    private func write(_ object: [String: Any]) {
        guard let input, var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        log?.write(Data("> ".utf8) + data)
        try? input.write(contentsOf: data)
    }

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty, let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            log?.write(Data("< ".utf8) + line + Data([0x0A]))
            handle(object)
        }
    }

    private func handle(_ m: [String: Any]) {
        let params = m["params"] as? [String: Any] ?? [:]
        if let method = m["method"] as? String {
            if let id = m["id"] {
                answer(id: id, method: method, params: params)
            } else if method == "session/update", let update = params["update"] as? [String: Any] {
                notify(update)
            }
            return
        }
        guard let id = m["id"] as? Int, let c = waiting.removeValue(forKey: id) else { return }
        if let error = m["error"] as? [String: Any] {
            let data = (error["data"] as? [String: Any])?["message"] as? String
            c.resume(throwing: AgentError(message: friendly(data ?? error["message"] as? String ?? "The agent hit an error.")))
        } else {
            c.resume(returning: Message(body: m["result"] as? [String: Any] ?? [:]))
        }
    }

    private func friendly(_ raw: String) -> String {
        if raw.localizedCaseInsensitiveContains("auth") || raw.localizedCaseInsensitiveContains("login") {
            return "The agent needs you to sign in. Run it once in Terminal to log in."
        }
        return raw.count > 160 ? String(raw.prefix(157)) + "…" : raw
    }

    private func answer(id: Any, method: String, params: [String: Any]) {
        var reply: [String: Any] = ["jsonrpc": "2.0", "id": id]
        switch method {
        case "fs/write_text_file":
            if let path = params["path"] as? String, let content = params["content"] as? String, inside(path) {
                do {
                    try content.write(toFile: path, atomically: true, encoding: .utf8)
                    reply["result"] = NSNull()
                } catch {
                    reply["error"] = ["code": -32000, "message": error.localizedDescription]
                }
            } else {
                reply["error"] = ["code": -32000, "message": "Quill only lets agents write inside the open folder."]
            }
        case "session/request_permission":
            let options = params["options"] as? [[String: Any]] ?? []
            let call = params["toolCall"] as? [String: Any] ?? [:]
            let kind = call["kind"] as? String ?? "other"
            let paths = (call["locations"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
            let safe = ["read", "edit", "search", "think", "fetch"].contains(kind) && paths.allSatisfy(inside)
            let wanted = safe ? "allow_once" : "reject_once"
            if let option = options.first(where: { $0["kind"] as? String == wanted }) ?? options.first(where: { ($0["kind"] as? String)?.hasPrefix(safe ? "allow" : "reject") == true }),
               let optionID = option["optionId"] {
                reply["result"] = ["outcome": ["outcome": "selected", "optionId": optionID]]
            } else {
                reply["result"] = ["outcome": ["outcome": "cancelled"]]
            }
        default:
            reply["error"] = ["code": -32601, "message": "Quill doesn't support \(method)."]
        }
        write(reply)
    }

    private func inside(_ path: String) -> Bool {
        guard let cwd else { return false }
        let root = cwd.standardizedFileURL.resolvingSymlinksInPath().path
        let target = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        return target == root || target.hasPrefix(root + "/")
    }

    private func notify(_ update: [String: Any]) {
        guard let events else { return }
        switch update["sessionUpdate"] as? String {
        case "agent_message_chunk":
            if let content = update["content"] as? [String: Any], let text = content["text"] as? String { events(.text(text)) }
        case "agent_thought_chunk":
            events(.activity("Thinking"))
        case "tool_call":
            events(.activity(activity(update)))
        default:
            break
        }
    }

    private func activity(_ call: [String: Any]) -> String {
        let file = (call["locations"] as? [[String: Any]])?.first?["path"] as? String
        let name = file.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        switch call["kind"] as? String {
        case "read": return name.map { "Reading \($0)" } ?? "Reading"
        case "edit": return name.map { "Editing \($0)" } ?? "Editing"
        case "search": return "Searching"
        case "fetch": return "Looking it up"
        default: return (call["title"] as? String) ?? "Working"
        }
    }
}

enum Keychain {
    static func read(_ account: String) -> String? {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Quill",
            kSecAttrAccount as String: account, kSecReturnData as String: true,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, _ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Quill", kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static var anthropicKey: String? {
        read("anthropic") ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }
}

@MainActor
final class AnthropicAgent: Agent {
    let canEditFiles = false
    private var task: Task<Void, Error>?
    private var previous: String?

    func prepare(cwd: URL) async throws {}

    func cancel() { task?.cancel() }

    func send(_ prompt: String, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws {
        guard let key = Keychain.anthropicKey, !key.isEmpty else {
            throw AgentError(message: "Add your Anthropic API key in Settings.")
        }
        var text = prompt
        if let previous { text = "Earlier in this session:\n\(previous)\n\n" + text }
        let body: [String: Any] = [
            "model": "claude-opus-5-5",
            "max_tokens": 64000,
            "stream": true,
            "output_config": ["effort": "low"],
            "fallbacks": "default",
            "system": "You work inside a text editor. When you change the document, write your one-sentence reply first, then call edit_document exactly once with every edit.",
            "tools": [[
                "name": "edit_document",
                "description": "Replace exact passages of the open document. Each find must be copied exactly from the document and be long enough to be unique.",
                "strict": true,
                "eager_input_streaming": true,
                "input_schema": [
                    "type": "object", "additionalProperties": false, "required": ["edits"],
                    "properties": ["edits": [
                        "type": "array",
                        "items": [
                            "type": "object", "additionalProperties": false, "required": ["find", "replace"],
                            "properties": ["find": ["type": "string"], "replace": ["type": "string"]],
                        ],
                    ]],
                ],
            ]],
            "messages": [["role": "user", "content": text]],
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        events(.activity("Thinking"))
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            var raw = ""
            for try await line in bytes.lines { raw += line }
            let message = ((try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
            throw AgentError(message: status == 401 ? "That API key didn't work." : message ?? "The API returned \(status).")
        }

        var reply = ""
        var json: [Int: String] = [:]
        var working = base
        for try await line in bytes.lines {
            guard line.hasPrefix("data: "), let event = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any] else { continue }
            let index = event["index"] as? Int ?? 0
            switch event["type"] as? String {
            case "content_block_start":
                if (event["content_block"] as? [String: Any])?["type"] as? String == "tool_use" {
                    json[index] = ""
                    events(.activity("Editing"))
                }
            case "content_block_delta":
                let delta = event["delta"] as? [String: Any] ?? [:]
                if let t = delta["text"] as? String { reply += t; events(.text(t)) }
                if let p = delta["partial_json"] as? String { json[index, default: ""] += p }
            case "content_block_stop":
                guard let raw = json.removeValue(forKey: index) else { break }
                guard let input = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                      let edits = input["edits"] as? [[String: String]]
                else { throw AgentError(message: "The edit came back malformed. Try again.") }
                let doc = NSMutableString(string: working)
                for edit in edits {
                    guard let find = edit["find"], let replace = edit["replace"], !find.isEmpty else { continue }
                    let r = doc.range(of: find)
                    if r.location != NSNotFound { doc.replaceCharacters(in: r, with: replace) }
                }
                working = doc as String
                events(.proposed(working))
            case "message_delta":
                if (event["delta"] as? [String: Any])?["stop_reason"] as? String == "refusal" {
                    throw AgentError(message: "Claude declined that one.")
                }
            case "error":
                throw AgentError(message: ((event["error"] as? [String: Any])?["message"] as? String) ?? "The API hit an error.")
            default:
                break
            }
        }
        previous = "They said: \(prompt.components(separatedBy: "\n").dropFirst(2).first ?? "")\nYou replied: \(reply)"
    }
}

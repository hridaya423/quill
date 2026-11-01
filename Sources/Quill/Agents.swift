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
    func shutdown()
}

struct AgentSpec: Identifiable, Hashable {
    enum Kind: Hashable { case acp(String), codex, anthropic }
    var id: String
    var name: String
    var detail: String
    var kind: Kind
    var requires: String?

    static let all: [AgentSpec] = [
        AgentSpec(id: "claude", name: "Claude Code", detail: "Your Claude subscription, through Claude Code",
                  kind: .acp("npx -y @agentclientprotocol/claude-agent-acp@0.99.1"), requires: "claude"),
        AgentSpec(id: "codex", name: "Codex", detail: "Your ChatGPT subscription, through the Codex CLI",
                  kind: .codex, requires: "codex"),
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
        case .codex: CodexAgent()
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
final class RPC {
    var onRequest: ((String, [String: Any]) -> [String: Any])?
    var onNotify: ((String, [String: Any]) -> Void)?
    var onExit: (() -> Void)?
    private let process: Process
    private let input: FileHandle
    private var buffer = Data()
    private var nextID = 0
    private var waiting: [Int: CheckedContinuation<Message, Error>] = [:]

    private static let log: FileHandle? = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appending(path: "Logs/Quill")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "agent.log")
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: file)
        _ = try? h?.seekToEnd()
        return h
    }()

    init(command: String, cwd: URL) throws {
        process = loginShell("exec \(command)")
        process.currentDirectoryURL = cwd
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        input = stdin.fileHandleForWriting
        let log = Self.log
        stderr.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if !d.isEmpty { log?.write(d) }
        }
        stdout.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            Task { @MainActor in self?.ingest(d) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.died() }
        }
        try process.run()
    }

    var running: Bool { process.isRunning }

    func stop() {
        if process.isRunning { process.terminate() }
    }

    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        let message = try await withCheckedThrowingContinuation { c in
            waiting[id] = c
            write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        }
        return message.body
    }

    func notify(_ method: String, _ params: [String: Any] = [:]) {
        write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func died() {
        for (_, c) in waiting { c.resume(throwing: AgentError(message: "The agent stopped. Check that it's installed and signed in.")) }
        waiting = [:]
        onExit?()
    }

    private func write(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        Self.log?.write(Data("> ".utf8) + data)
        try? input.write(contentsOf: data)
    }

    private func ingest(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty, let m = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            Self.log?.write(Data("< ".utf8) + line + Data([0x0A]))
            let params = m["params"] as? [String: Any] ?? [:]
            if let method = m["method"] as? String {
                if let id = m["id"] {
                    var reply = onRequest?(method, params) ?? ["error": ["code": -32601, "message": "Quill doesn't support \(method)."]]
                    reply["jsonrpc"] = "2.0"
                    reply["id"] = id
                    write(reply)
                } else {
                    onNotify?(method, params)
                }
            } else if let id = m["id"] as? Int, let c = waiting.removeValue(forKey: id) {
                if let error = m["error"] as? [String: Any] {
                    let detail = (error["data"] as? [String: Any])?["message"] as? String
                    c.resume(throwing: AgentError(message: friendly(detail ?? error["message"] as? String ?? "The agent hit an error.")))
                } else {
                    c.resume(returning: Message(body: m["result"] as? [String: Any] ?? [:]))
                }
            }
        }
    }
}

func friendly(_ raw: String) -> String {
    if raw.localizedCaseInsensitiveContains("auth") || raw.localizedCaseInsensitiveContains("log in") || raw.localizedCaseInsensitiveContains("login") {
        return "The agent needs you to sign in. Run it once in Terminal to log in."
    }
    return raw.count > 160 ? String(raw.prefix(157)) + "…" : raw
}

func inside(_ path: String, _ root: URL) -> Bool {
    let base = root.standardizedFileURL.resolvingSymlinksInPath().path
    let target = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    return target == base || target.hasPrefix(base + "/")
}

@MainActor
final class ACPAgent: Agent {
    let command: String
    let canEditFiles = true
    private var rpc: RPC?
    private var session: String?
    private var cwd: URL?
    private var starting: Task<Void, Error>?
    private var events: (@MainActor (AgentEvent) -> Void)?

    init(command: String) {
        self.command = command
    }

    func prepare(cwd: URL) async throws {
        if session != nil, self.cwd == cwd, rpc?.running == true { return }
        if let starting { return try await starting.value }
        let task = Task { try await self.boot(cwd: cwd) }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    private func boot(cwd: URL) async throws {
        rpc?.stop()
        let rpc = try RPC(command: command, cwd: cwd)
        self.rpc = rpc
        self.cwd = cwd
        rpc.onRequest = { [weak self] method, params in self?.answer(method, params) ?? [:] }
        rpc.onNotify = { [weak self] method, params in
            if method == "session/update", let update = params["update"] as? [String: Any] { self?.notify(update) }
        }
        rpc.onExit = { [weak self] in self?.session = nil }
        _ = try await rpc.request("initialize", [
            "protocolVersion": 1,
            "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": true], "terminal": false],
            "clientInfo": ["name": "Quill", "version": "0.1"],
        ])
        let created = try await rpc.request("session/new", ["cwd": cwd.path, "mcpServers": []])
        guard let id = created["sessionId"] as? String else { throw AgentError(message: "The agent didn't open a session.") }
        session = id
    }

    func send(_ prompt: String, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws {
        guard let cwd else { throw AgentError(message: "The agent isn't ready yet.") }
        try await prepare(cwd: cwd)
        guard let session, let rpc else { throw AgentError(message: "The agent isn't ready yet.") }
        self.events = events
        defer { self.events = nil }
        let result = try await rpc.request("session/prompt", ["sessionId": session, "prompt": [["type": "text", "text": prompt]]])
        if result["stopReason"] as? String == "refusal" {
            throw AgentError(message: "The agent declined that one.")
        }
    }

    func cancel() {
        guard let session else { return shutdown() }
        rpc?.notify("session/cancel", ["sessionId": session])
    }

    func shutdown() {
        rpc?.stop()
        session = nil
    }

    private func answer(_ method: String, _ params: [String: Any]) -> [String: Any] {
        guard let cwd else { return ["error": ["code": -32000, "message": "No folder is open."]] }
        switch method {
        case "fs/write_text_file":
            guard let path = params["path"] as? String, let content = params["content"] as? String, inside(path, cwd) else {
                return ["error": ["code": -32000, "message": "Quill only lets agents write inside the open folder."]]
            }
            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                return ["result": NSNull()]
            } catch {
                return ["error": ["code": -32000, "message": error.localizedDescription]]
            }
        case "session/request_permission":
            let options = params["options"] as? [[String: Any]] ?? []
            let call = params["toolCall"] as? [String: Any] ?? [:]
            let kind = call["kind"] as? String ?? "other"
            let locations = call["locations"] as? [[String: Any]] ?? []
            let paths = locations.compactMap { $0["path"] as? String }
            let inVault = !paths.isEmpty && paths.count == locations.count && paths.allSatisfy { inside($0, cwd) }
            let safe = ["think", "fetch"].contains(kind) || (["read", "edit", "search"].contains(kind) && inVault)
            let option = safe
                ? options.first { $0["kind"] as? String == "allow_once" }
                : options.first { ($0["kind"] as? String)?.hasPrefix("reject") == true }
            guard let id = option?["optionId"] else { return ["result": ["outcome": ["outcome": "cancelled"]]] }
            return ["result": ["outcome": ["outcome": "selected", "optionId": id]]]
        default:
            return ["error": ["code": -32601, "message": "Quill doesn't support \(method)."]]
        }
    }

    private func notify(_ update: [String: Any]) {
        guard let events else { return }
        switch update["sessionUpdate"] as? String {
        case "agent_message_chunk":
            if let content = update["content"] as? [String: Any], let text = content["text"] as? String { events(.text(text)) }
        case "agent_thought_chunk":
            events(.activity("Thinking"))
        case "tool_call":
            let file = (update["locations"] as? [[String: Any]])?.first?["path"] as? String
            events(.activity(activity(update["kind"] as? String, file: file, title: update["title"] as? String)))
        default:
            break
        }
    }
}

func activity(_ kind: String?, file: String?, title: String?) -> String {
    let name = file.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
    switch kind {
    case "read": return name.map { "Reading \($0)" } ?? "Reading"
    case "edit": return name.map { "Editing \($0)" } ?? "Editing"
    case "search": return "Searching"
    case "fetch": return "Looking it up"
    default: return title ?? "Working"
    }
}

@MainActor
final class CodexAgent: Agent {
    let canEditFiles = true
    private var rpc: RPC?
    private var thread: String?
    private var turn: String?
    private var cwd: URL?
    private var starting: Task<Void, Error>?
    private var events: (@MainActor (AgentEvent) -> Void)?
    private var finished: CheckedContinuation<Void, Error>?

    func prepare(cwd: URL) async throws {
        if thread != nil, self.cwd == cwd, rpc?.running == true { return }
        if let starting { return try await starting.value }
        let task = Task { try await self.boot(cwd: cwd) }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    private func boot(cwd: URL) async throws {
        rpc?.stop()
        let rpc = try RPC(command: "codex app-server", cwd: cwd)
        self.rpc = rpc
        self.cwd = cwd
        rpc.onRequest = { method, _ in
            ["result": ["decision": method.contains("fileChange") || method == "applyPatchApproval" ? "accept" : "decline"]]
        }
        rpc.onNotify = { [weak self] method, params in self?.notify(method, params) }
        rpc.onExit = { [weak self] in
            self?.thread = nil
            self?.finish(AgentError(message: "Codex stopped. Check that it's installed and signed in."))
        }
        _ = try await rpc.request("initialize", ["clientInfo": ["name": "quill", "title": "Quill", "version": "0.1"]])
        rpc.notify("initialized")
        let started = try await rpc.request("thread/start", [
            "cwd": cwd.path, "sandbox": "workspace-write", "approvalPolicy": "never", "ephemeral": true,
        ])
        guard let id = (started["thread"] as? [String: Any])?["id"] as? String else {
            throw AgentError(message: "Codex didn't open a thread.")
        }
        thread = id
    }

    func send(_ prompt: String, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws {
        guard let cwd else { throw AgentError(message: "Codex isn't ready yet.") }
        try await prepare(cwd: cwd)
        guard let thread, let rpc else { throw AgentError(message: "Codex isn't ready yet.") }
        self.events = events
        defer { self.events = nil; turn = nil }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            finished = c
            Task {
                do {
                    let r = try await rpc.request("turn/start", [
                        "threadId": thread, "effort": "low", "input": [["type": "text", "text": prompt]],
                    ])
                    turn = (r["turn"] as? [String: Any])?["id"] as? String
                } catch {
                    finish(error)
                }
            }
        }
    }

    func shutdown() {
        rpc?.stop()
        thread = nil
    }

    func cancel() {
        guard let thread, let turn else { return shutdown() }
        Task { _ = try? await rpc?.request("turn/interrupt", ["threadId": thread, "turnId": turn]) }
    }

    private func finish(_ error: Error?) {
        guard let c = finished else { return }
        finished = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }

    private func notify(_ method: String, _ params: [String: Any]) {
        switch method {
        case "item/agentMessage/delta":
            if let delta = params["delta"] as? String { events?(.text(delta)) }
        case "item/started":
            switch (params["item"] as? [String: Any])?["type"] as? String {
            case "reasoning": events?(.activity("Thinking"))
            case "commandExecution", "fileChange": events?(.activity("Editing"))
            default: break
            }
        case "turn/completed":
            let t = params["turn"] as? [String: Any]
            if t?["status"] as? String == "failed" {
                let message = (t?["error"] as? [String: Any])?["message"] as? String
                finish(AgentError(message: friendly(message ?? "Codex couldn't finish that.")))
            } else {
                finish(nil)
            }
        default:
            break
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
    private var previous: String?

    func prepare(cwd: URL) async throws {}

    func cancel() {}

    func shutdown() {}

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
        var complete = false
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
                guard let next = replacing(edits.map { (find: $0["find"] ?? "", replace: $0["replace"] ?? "") }, in: working)
                else { throw AgentError(message: "The edit didn't match the document. Try again.") }
                working = next
                events(.proposed(working))
            case "message_delta":
                if (event["delta"] as? [String: Any])?["stop_reason"] as? String == "refusal" {
                    throw AgentError(message: "Claude declined that one.")
                }
            case "message_stop":
                complete = true
            case "error":
                throw AgentError(message: ((event["error"] as? [String: Any])?["message"] as? String) ?? "The API hit an error.")
            default:
                break
            }
        }
        guard complete else { throw AgentError(message: "The connection dropped. Try again.") }
        previous = "They said: \(prompt.components(separatedBy: "\n").dropFirst(2).first ?? "")\nYou replied: \(reply)"
    }
}

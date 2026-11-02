import Foundation
import QuillCore

enum AgentEvent {
    case activity(String)
    case text(String)
    case proposed(String)
    case notes(String)
    case focus(String)
    case read(String)
}

struct AgentError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

struct ModelChoice: Hashable, Identifiable {
    var id: String
    var name: String
}

@MainActor
protocol Agent: AnyObject {
    var canEditFiles: Bool { get }
    var conversation: String? { get }
    var model: ModelChoice? { get }
    var models: [ModelChoice] { get }
    func prepare(cwd: URL, readable: [URL]) async throws
    func choose(model: String) async throws
    func send(_ prompt: String, file: URL?, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws
    func cancel()
    func shutdown()
}

struct AgentSpec: Identifiable, Hashable {
    enum Kind: Hashable {
        case acp([String])
        case registry(String, local: [String]?, npx: Bool)
        case codex([String])
        case api
    }
    var id: String
    var name: String
    var detail: String
    var kind: Kind
    var defaultModel: String?
    var mark: String
    var install: String?
    var picks: [String] = []

    static let all: [AgentSpec] = [
        AgentSpec(id: "claude", name: "Claude Code", detail: "Claude plan", kind: .acp(["npx", "-y", "@agentclientprotocol/claude-agent-acp@0.99.1"]),
                  defaultModel: "opus", mark: "claude", install: "Needs Node: nodejs.org", picks: ["opus", "sonnet", "haiku"]),
        AgentSpec(id: "codex", name: "Codex", detail: "ChatGPT plan", kind: .codex(["codex", "app-server"]),
                  mark: "codex", install: "npm install -g @openai/codex"),
        AgentSpec(id: "cursor", name: "Cursor", detail: "Cursor plan", kind: .registry("cursor", local: nil, npx: false),
                  mark: "cursor", install: "Downloads on first use. Sign in with cursor-agent login."),
        AgentSpec(id: "gemini", name: "Gemini CLI", detail: "Google account", kind: .registry("gemini", local: ["gemini", "--acp"], npx: true),
                  mark: "gemini", install: "Needs Node: nodejs.org"),
        AgentSpec(id: "grok", name: "Grok Build", detail: "xAI account", kind: .registry("grok-build", local: ["grok", "agent", "stdio"], npx: true),
                  mark: "grok", install: "Needs Node: nodejs.org"),
        AgentSpec(id: "opencode", name: "OpenCode", detail: "Any provider", kind: .registry("opencode", local: ["opencode", "acp"], npx: false),
                  mark: "opencode", install: "Downloads on first use."),
        AgentSpec(id: "antigravity", name: "Antigravity", detail: "Google account", kind: .registry("antigravity-acp", local: nil, npx: false),
                  mark: "antigravity", install: "Downloads on first use."),
        AgentSpec(id: "devin", name: "Devin", detail: "Devin account", kind: .registry("devin", local: ["devin", "acp"], npx: false),
                  mark: "devin", install: "Downloads on first use. Sign in with devin auth login."),
        AgentSpec(id: "pi", name: "Pi", detail: "Any provider", kind: .registry("pi-acp", local: ["pi-acp"], npx: true),
                  mark: "pi", install: "npm install -g @mariozechner/pi-coding-agent"),
        AgentSpec(id: "fx", name: "fx", detail: "fx account", kind: .acp(["fx", "acp"]),
                  mark: "fx", install: "Install fx, then sign in with fx login."),
        AgentSpec(id: "api", name: "Your API", detail: "Key and URL", kind: .api, mark: "api"),
    ]

    static func named(_ id: String) -> AgentSpec { all.first { $0.id == id } ?? all[0] }

    var binaries: [String] {
        switch kind {
        case .acp(let argv), .codex(let argv): [argv[0]]
        case .registry(_, let local, let npx): npx ? (local.map { [$0[0]] } ?? []) + ["npx"] : []
        case .api: []
        }
    }

    var api: Bool { kind == .api }

    var missing: String {
        switch kind {
        case .api: "Needs a URL"
        case .registry(_, _, true): "Needs Node"
        case .acp(let argv) where argv[0] == "npx": "Needs Node"
        default: "Not installed"
        }
    }

    var need: String {
        switch kind {
        case .api: "a URL"
        case .registry(_, _, true): "Node"
        case .acp(let argv) where argv[0] == "npx": "Node"
        case .acp(let argv), .codex(let argv): "the \(argv[0]) command"
        case .registry: "a download"
        }
    }

    @MainActor func make() -> Agent {
        let preferred = Prefs.model(id) ?? defaultModel
        return switch kind {
        case .acp(let argv): ACPAgent(launch: { argv }, preferred: preferred)
        case .registry(let agent, let local, _): ACPAgent(launch: { try await Registry.argv(agent, local: local) }, preferred: preferred)
        case .codex(let argv): CodexAgent(argv: argv, preferred: preferred)
        case .api:
            if let host = URL(string: Prefs.endpoint)?.host, host.hasSuffix("anthropic.com") {
                AnthropicAgent(base: Prefs.endpoint, model: preferred ?? "claude-opus-5-5")
            } else {
                ChatAgent(id: id, base: Prefs.endpoint, effort: URL(string: Prefs.endpoint)?.host == "api.openai.com", preferred: preferred)
            }
        }
    }
}

@MainActor
enum Shell {
    private static var resolving: Task<String, Never>?

    static func path() async -> String {
        if let resolving { return await resolving.value }
        let task = Task.detached { loginPath() }
        resolving = task
        return await task.value
    }

    nonisolated private static func loginPath() -> String {
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let fallback = inherited + ":/opt/homebrew/bin:/usr/local/bin:" + NSHomeDirectory() + "/.local/bin"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        p.arguments = ["-ilc", "printf '\\n__QUILL_PATH__%s\\n' \"$PATH\""]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return fallback }
        let deadline = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: deadline)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        deadline.cancel()
        let marker = "__QUILL_PATH__"
        guard let line = String(decoding: data, as: UTF8.self).split(separator: "\n").last(where: { $0.hasPrefix(marker) }) else { return fallback }
        return String(line.dropFirst(marker.count))
    }

    static func find(_ binary: String) async -> URL? {
        if binary.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: binary) ? URL(fileURLWithPath: binary) : nil }
        for dir in await path().split(separator: ":") {
            let url = URL(fileURLWithPath: String(dir)).appending(path: binary)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    static func process(_ argv: [String], cwd: URL) async -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = argv
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = await path()
        p.environment = env
        p.currentDirectoryURL = cwd
        return p
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

    init(_ process: Process) throws {
        self.process = process
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

func same(_ path: String, _ file: URL) -> Bool {
    URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path == file.standardizedFileURL.resolvingSymlinksInPath().path
}

func permits(kind: String, paths: [String], file: URL?, readable: [URL]) -> Bool {
    switch kind {
    case "think", "fetch":
        return true
    case "read", "search":
        return paths.allSatisfy { p in (file.map { same(p, $0) } ?? false) || readable.contains { inside(p, $0) } || browsable(p) }
    case "edit":
        guard let file else { return false }
        return !paths.isEmpty && paths.allSatisfy { same($0, file) }
    default:
        return false
    }
}

func choices(from configOptions: Any?, id: String) -> (current: String?, options: [ModelChoice]) {
    guard let option = (configOptions as? [[String: Any]])?.first(where: { $0["id"] as? String == id }) else { return (nil, []) }
    let flat = (option["options"] as? [[String: Any]] ?? []).flatMap { o in (o["options"] as? [[String: Any]]) ?? [o] }
    let options = flat.compactMap { o -> ModelChoice? in
        guard let value = o["value"] as? String, let name = o["name"] as? String else { return nil }
        return ModelChoice(id: value, name: value == "default" ? (o["description"] as? String).map { "\($0) (default)" } ?? name : name)
    }
    return (option["currentValue"] as? String, options)
}

@MainActor
final class ACPAgent: Agent {
    let launch: () async throws -> [String]
    let canEditFiles = true
    var conversation: String? { session }
    private(set) var model: ModelChoice?
    private(set) var models: [ModelChoice] = []
    private var preferred: String?
    private var rpc: RPC?
    private var session: String?
    private var cwd: URL?
    private var readable: [URL] = []
    private var file: URL?
    private var starting: Task<Void, Error>?
    private var events: (@MainActor (AgentEvent) -> Void)?

    init(launch: @escaping () async throws -> [String], preferred: String?) {
        self.launch = launch
        self.preferred = preferred
    }

    func prepare(cwd: URL, readable: [URL]) async throws {
        self.readable = readable
        if session != nil, self.cwd == cwd, rpc?.running == true { return }
        if let starting { return try await starting.value }
        let task = Task { try await self.boot(cwd: cwd) }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    private func boot(cwd: URL) async throws {
        rpc?.stop()
        let rpc = try RPC(await Shell.process(try await launch(), cwd: cwd))
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
            "clientInfo": ["name": "Quill", "version": "0.2"],
        ])
        let created = try await rpc.request("session/new", ["cwd": cwd.path, "mcpServers": []])
        guard let id = created["sessionId"] as? String else { throw AgentError(message: "The agent didn't open a session.") }
        session = id
        adopt(created["configOptions"])
        if let preferred, model?.id != preferred, models.contains(where: { $0.id == preferred }) {
            try? await set("model", preferred)
        }
        if choices(from: created["configOptions"], id: "effort").options.contains(where: { $0.id == "low" }) {
            try? await set("effort", "low")
        }
    }

    private func adopt(_ configOptions: Any?) {
        let found = choices(from: configOptions, id: "model")
        guard !found.options.isEmpty else { return }
        models = found.options
        model = found.options.first { $0.id == found.current }
    }

    private func set(_ config: String, _ value: String) async throws {
        guard let rpc, let session else { return }
        let result = try await rpc.request("session/set_config_option", ["sessionId": session, "configId": config, "value": value])
        adopt(result["configOptions"])
    }

    func choose(model value: String) async throws {
        preferred = value
        try await set("model", value)
    }

    func send(_ prompt: String, file: URL?, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws {
        guard let cwd else { throw AgentError(message: "The agent isn't ready yet.") }
        try await prepare(cwd: cwd, readable: readable)
        guard let session, let rpc else { throw AgentError(message: "The agent isn't ready yet.") }
        self.file = file
        self.events = events
        defer { self.events = nil; self.file = nil }
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

    func answer(_ method: String, _ params: [String: Any]) -> [String: Any] {
        switch method {
        case "fs/write_text_file":
            guard let path = params["path"] as? String, let content = params["content"] as? String, let file, same(path, file) else {
                return ["error": ["code": -32000, "message": "Quill only lets the agent write its working copy of the note."]]
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
            if let old = (call["rawInput"] as? [String: Any])?["old_string"] as? String, !old.isEmpty { events?(.focus(old)) }
            let locations = call["locations"] as? [[String: Any]] ?? []
            let paths = locations.compactMap { $0["path"] as? String }
            let kind = call["kind"] as? String ?? "other"
            let allowed = paths.count == locations.count && permits(kind: kind, paths: paths, file: file, readable: readable)
            if allowed, kind == "read" { paths.forEach { events?(.read($0)) } }
            let option = allowed
                ? options.first { $0["kind"] as? String == "allow_once" }
                : options.first { ($0["kind"] as? String)?.hasPrefix("reject") == true }
            guard let id = option?["optionId"] else { return ["result": ["outcome": ["outcome": "cancelled"]]] }
            return ["result": ["outcome": ["outcome": "selected", "optionId": id]]]
        default:
            return ["error": ["code": -32601, "message": "Quill doesn't support \(method)."]]
        }
    }

    private func notify(_ update: [String: Any]) {
        switch update["sessionUpdate"] as? String {
        case "config_option_update":
            adopt(update["configOptions"])
        case "agent_message_chunk":
            if let content = update["content"] as? [String: Any], let text = content["text"] as? String { events?(.text(text)) }
        case "agent_thought_chunk":
            events?(.activity("Thinking"))
        case "tool_call_update":
            if let old = (update["rawInput"] as? [String: Any])?["old_string"] as? String, !old.isEmpty { events?(.focus(old)) }
        case "tool_call":
            let file = (update["locations"] as? [[String: Any]])?.first?["path"] as? String
            events?(.activity(activity(update["kind"] as? String, file: file, title: update["title"] as? String)))
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
    let argv: [String]
    let canEditFiles = true
    var conversation: String? { thread }
    private(set) var models: [ModelChoice] = []
    private var preferred: String?
    private var rpc: RPC?
    private var thread: String?
    private var turn: String?
    private var cwd: URL?
    private var starting: Task<Void, Error>?
    private var events: (@MainActor (AgentEvent) -> Void)?
    private var finished: CheckedContinuation<Void, Error>?
    private var current: String?

    init(argv: [String], preferred: String?) {
        self.argv = argv
        self.preferred = preferred
    }

    var model: ModelChoice? { models.first { $0.id == (preferred ?? current) } }

    func prepare(cwd: URL, readable: [URL]) async throws {
        if thread != nil, self.cwd == cwd, rpc?.running == true { return }
        if let starting { return try await starting.value }
        let task = Task { try await self.boot(cwd: cwd) }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    private func boot(cwd: URL) async throws {
        rpc?.stop()
        let rpc = try RPC(await Shell.process(argv, cwd: cwd))
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
        _ = try await rpc.request("initialize", ["clientInfo": ["name": "quill", "title": "Quill", "version": "0.2"]])
        rpc.notify("initialized")
        if let listed = try? await rpc.request("model/list", [:]), let data = listed["data"] as? [[String: Any]] {
            models = data.compactMap { m in
                guard let id = m["id"] as? String else { return nil }
                if m["isDefault"] as? Bool == true { current = id }
                return ModelChoice(id: id, name: m["displayName"] as? String ?? id)
            }
        }
        var params: [String: Any] = ["cwd": cwd.path, "sandbox": "workspace-write", "approvalPolicy": "never", "ephemeral": true]
        if let preferred { params["model"] = preferred }
        let started = try await rpc.request("thread/start", params)
        guard let id = (started["thread"] as? [String: Any])?["id"] as? String else {
            throw AgentError(message: "Codex didn't open a thread.")
        }
        if let used = started["model"] as? String { current = used }
        thread = id
    }

    func choose(model value: String) async throws {
        preferred = value
    }

    func send(_ prompt: String, file: URL?, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws {
        guard let cwd else { throw AgentError(message: "Codex isn't ready yet.") }
        try await prepare(cwd: cwd, readable: [])
        guard let thread, let rpc else { throw AgentError(message: "Codex isn't ready yet.") }
        self.events = events
        defer { self.events = nil; turn = nil }
        var params: [String: Any] = ["threadId": thread, "effort": "low", "input": [["type": "text", "text": prompt]]]
        if let preferred { params["model"] = preferred }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            finished = c
            Task {
                do {
                    let r = try await rpc.request("turn/start", params)
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
        guard !value.isEmpty else {
            SecItemDelete(base as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        if SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static var apiKey: String? {
        read("api").flatMap { $0.isEmpty ? nil : $0 } ?? ProcessInfo.processInfo.environment["QUILL_API_KEY"]
    }
}

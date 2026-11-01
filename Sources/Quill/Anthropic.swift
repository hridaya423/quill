import Foundation
import QuillCore

@MainActor
final class AnthropicAgent: Agent {
    let canEditFiles = false
    let conversation: String? = nil
    let models = [
        ModelChoice(id: "claude-opus-5-5", name: "Claude Opus 5.5"),
        ModelChoice(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5"),
        ModelChoice(id: "claude-haiku-5-5", name: "Claude Haiku 5.5"),
    ]
    private var chosen: String
    private var previous: String?
    private var live: URLSessionDataTask?

    init(model: String) {
        chosen = model
    }

    var model: ModelChoice? { models.first { $0.id == chosen } }

    func prepare(cwd: URL, readable: [URL]) async throws {}

    func choose(model: String) async throws {
        chosen = model
    }

    func cancel() {
        live?.cancel()
    }

    func shutdown() {
        live?.cancel()
    }

    static let system = """
    You work inside a text editor. To change the document, write your one-sentence reply first, then call edit_document once with every edit. \
    To leave margin notes, call leave_notes once.
    """

    static let tools: [[String: Any]] = [
        [
            "name": "edit_document",
            "description": "Replace exact passages of the open document. Each find is copied exactly from the document and is long enough to be unique. Edits must not overlap.",
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
        ],
        [
            "name": "leave_notes",
            "description": "Leave margin notes on the document without changing it. Each quote is copied exactly from the document, 3 to 12 words.",
            "strict": true,
            "eager_input_streaming": true,
            "input_schema": [
                "type": "object", "additionalProperties": false, "required": ["notes"],
                "properties": ["notes": [
                    "type": "array",
                    "items": [
                        "type": "object", "additionalProperties": false, "required": ["quote", "lens", "note"],
                        "properties": [
                            "quote": ["type": "string"],
                            "lens": ["type": "string", "enum": lenses],
                            "note": ["type": "string"],
                        ],
                    ],
                ]],
            ],
        ],
    ]

    func body(_ text: String) -> [String: Any] {
        var body: [String: Any] = [
            "model": chosen,
            "max_tokens": 32000,
            "stream": true,
            "output_config": ["effort": "low"],
            "system": Self.system,
            "tools": Self.tools,
            "messages": [["role": "user", "content": text]],
        ]
        if !chosen.contains("haiku") { body["fallbacks"] = "default" }
        return body
    }

    func send(_ prompt: String, file: URL?, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws {
        guard let key = Keychain.anthropicKey, !key.isEmpty else {
            throw AgentError(message: "Add your Anthropic API key in Settings.")
        }
        var text = prompt
        if let previous { text = "Earlier in this session:\n\(previous)\n\n" + text }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if !chosen.contains("haiku") { request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body(text))

        events(.activity("Thinking"))
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        live = bytes.task
        defer { live = nil }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            var raw = ""
            for try await line in bytes.lines { raw += line }
            let message = ((try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
            throw AgentError(message: status == 401 ? "That API key didn't work." : message.map(friendly) ?? "The API returned \(status).")
        }

        var reply = ""
        var tools: [Int: (name: String, scanner: ItemScanner)] = [:]
        var proposed = 0
        var stop: String?
        for try await line in bytes.lines {
            guard line.hasPrefix("data: "), let event = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any] else { continue }
            let index = event["index"] as? Int ?? 0
            switch event["type"] as? String {
            case "content_block_start":
                let block = event["content_block"] as? [String: Any]
                if block?["type"] as? String == "tool_use", let name = block?["name"] as? String {
                    tools[index] = (name, ItemScanner())
                    events(.activity(name == "leave_notes" ? "Reading closely" : "Editing"))
                }
            case "content_block_delta":
                let delta = event["delta"] as? [String: Any] ?? [:]
                if let t = delta["text"] as? String {
                    reply += t
                    events(.text(t))
                }
                if let p = delta["partial_json"] as? String, var tool = tools[index] {
                    let prefix = tool.scanner.feed(p)
                    tools[index] = tool
                    if tool.name == "edit_document", let prefix, let edits = Self.edits(prefix), edits.count > proposed,
                       let next = replacing(edits, in: base) {
                        if let last = edits.last { events(.focus(last.find)) }
                        proposed = edits.count
                        events(.proposed(next))
                    }
                }
            case "content_block_stop":
                guard let tool = tools.removeValue(forKey: index) else { break }
                let raw = tool.scanner.raw
                if tool.name == "leave_notes" {
                    guard let input = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], let notes = input["notes"],
                          let data = try? JSONSerialization.data(withJSONObject: notes)
                    else { throw AgentError(message: "The notes came back malformed. Try again.") }
                    events(.notes(String(decoding: data, as: UTF8.self)))
                } else {
                    guard let edits = Self.edits(raw) else { throw AgentError(message: "The edit came back malformed. Try again.") }
                    guard let next = replacing(edits, in: base) else { throw AgentError(message: "The edit didn't match the note. Try again.") }
                    if edits.count > proposed { events(.proposed(next)) }
                    proposed = edits.count
                }
            case "message_delta":
                stop = (event["delta"] as? [String: Any])?["stop_reason"] as? String ?? stop
                if stop == "refusal" { throw AgentError(message: "Claude declined that one.") }
            case "message_stop":
                if stop == "max_tokens" { throw AgentError(message: "The answer ran past its length limit. Ask for a smaller change.") }
                let lines = prompt.components(separatedBy: "\n")
                let asked = lines.firstIndex { $0.hasSuffix("They just said:") }.flatMap { lines.indices.contains($0 + 2) ? lines[$0 + 2] : nil }
                previous = "They said: \(asked ?? "")\nYou replied: \(reply)"
                return
            case "error":
                let message = (event["error"] as? [String: Any])?["message"] as? String
                throw AgentError(message: message.map(friendly) ?? "The API hit an error.")
            default:
                break
            }
        }
        throw AgentError(message: "The connection dropped. Try again.")
    }

    static func edits(_ raw: String) -> [(find: String, replace: String)]? {
        guard let input = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let items = input["edits"] as? [[String: Any]]
        else { return nil }
        let edits = items.compactMap { item -> (find: String, replace: String)? in
            guard let find = item["find"] as? String, let replace = item["replace"] as? String else { return nil }
            return (find, replace)
        }
        return edits.count == items.count ? edits : nil
    }
}

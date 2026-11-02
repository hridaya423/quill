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
    private var readable: [URL] = []
    private var live: URLSessionDataTask?

    let base: String

    init(base: String, model: String) {
        self.base = base
        chosen = model
    }

    var model: ModelChoice? { models.first { $0.id == chosen } }

    func prepare(cwd: URL, readable: [URL]) async throws {
        self.readable = readable
    }

    func choose(model: String) async throws {
        chosen = model
    }

    func cancel() {
        live?.cancel()
    }

    func shutdown() {
        live?.cancel()
    }

    static var tools: [[String: Any]] {
        Tool.all.map { ["name": $0.name, "description": $0.description, "strict": true, "eager_input_streaming": true, "input_schema": $0.parameters] }
    }

    func body(_ messages: [[String: Any]]) -> [String: Any] {
        var body: [String: Any] = [
            "model": chosen,
            "max_tokens": 32000,
            "stream": true,
            "output_config": ["effort": "low"],
            "system": Tool.system,
            "tools": Self.tools,
            "messages": messages,
        ]
        if !chosen.contains("haiku") { body["fallbacks"] = "default" }
        return body
    }

    func send(_ prompt: String, file: URL?, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws {
        guard let key = Keychain.apiKey else {
            throw AgentError(message: "Add your API key in Settings.")
        }
        var text = prompt
        if let previous { text = "Earlier in this session:\n\(previous)\n\n" + text }
        var messages: [[String: Any]] = [["role": "user", "content": text]]
        let toolbox = Toolbox(doc: base, readable: readable, events: events)
        var reply = ""
        events(.activity("Thinking"))
        for _ in 0..<12 {
            var request = URLRequest(url: URL(string: base + "/messages")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 300
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            if !chosen.contains("haiku") { request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
            request.httpBody = try JSONSerialization.data(withJSONObject: body(messages))

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

            var blocks: [Int: [String: Any]] = [:]
            var results: [[String: Any]] = []
            var again = false
            var stop: String?
            var ended = false
            for try await line in bytes.lines {
                guard line.hasPrefix("data: "), let event = try JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any] else { continue }
                let index = event["index"] as? Int ?? 0
                switch event["type"] as? String {
                case "content_block_start":
                    let block = event["content_block"] as? [String: Any] ?? [:]
                    if block["type"] as? String == "tool_use", let name = block["name"] as? String {
                        blocks[index] = ["type": "tool_use", "id": block["id"] ?? "", "name": name, "input": [String: Any]()]
                        toolbox.start(index, name)
                    } else if block["type"] as? String == "text" {
                        blocks[index] = ["type": "text", "text": ""]
                    }
                case "content_block_delta":
                    let delta = event["delta"] as? [String: Any] ?? [:]
                    if let t = delta["text"] as? String {
                        reply += t
                        let before = blocks[index]?["text"] as? String ?? ""
                        blocks[index]?["text"] = before + t
                        events(.text(t))
                    }
                    if let p = delta["partial_json"] as? String { toolbox.feed(index, p) }
                case "content_block_stop":
                    guard let done = toolbox.finish(index) else { break }
                    let input = (try? JSONSerialization.jsonObject(with: Data(done.input.utf8))) ?? [String: Any]()
                    blocks[index]?["input"] = input
                    let use = blocks[index]?["id"] ?? ""
                    results.append(["type": "tool_result", "tool_use_id": use, "content": done.result.result])
                    again = again || done.result.again
                case "message_delta":
                    stop = (event["delta"] as? [String: Any])?["stop_reason"] as? String ?? stop
                    if stop == "refusal" { throw AgentError(message: "Claude declined that one.") }
                case "message_stop":
                    if stop == "max_tokens" { throw AgentError(message: "The answer ran past its length limit. Ask for a smaller change.") }
                    ended = true
                case "error":
                    let message = (event["error"] as? [String: Any])?["message"] as? String
                    throw AgentError(message: message.map(friendly) ?? "The API hit an error.")
                default:
                    break
                }
                if ended { break }
            }
            guard ended else { throw AgentError(message: "The connection dropped. Try again.") }
            guard stop == "tool_use", again else {
                let lines = prompt.components(separatedBy: "\n")
                let asked = lines.firstIndex { $0.hasSuffix("They just said:") }.flatMap { lines.indices.contains($0 + 2) ? lines[$0 + 2] : nil }
                previous = "They said: \(asked ?? "")\nYou replied: \(reply)"
                return
            }
            messages.append(["role": "assistant", "content": blocks.keys.sorted().compactMap { blocks[$0] }.filter { $0["type"] as? String != "text" || !($0["text"] as? String ?? "").isEmpty }])
            messages.append(["role": "user", "content": results])
        }
        throw AgentError(message: "That took too many steps. Try a narrower request.")
    }
}

import Foundation
import QuillCore

@MainActor
final class ChatAgent: Agent {
    let id: String
    let base: String
    let effort: Bool
    let canEditFiles = false
    let conversation: String? = nil
    private(set) var models: [ModelChoice] = []
    private var preferred: String?
    private var previous: String?
    private var readable: [URL] = []
    private var live: URLSessionDataTask?

    init(id: String, base: String, effort: Bool, preferred: String?) {
        self.id = id
        self.base = base
        self.effort = effort
        self.preferred = preferred
    }

    var model: ModelChoice? { models.first { $0.id == preferred } ?? models.first }

    private var key: String? { Keychain.key(for: id) }

    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: base + path)!)
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization") }
        return request
    }

    static let unfit = ["embed", "tts", "whisper", "transcribe", "audio", "realtime", "image", "sora", "moderation", "search",
                        "deep-research", "guard", "orpheus", "babbage", "davinci", "instruct", "dall-e", "codex", "-pro", "vision", "ocr"]

    static func chatModels(_ ids: [String]) -> [String] {
        ids.filter { id in
            let lower = id.lowercased()
            return !unfit.contains { lower.contains($0) } && lower.range(of: #"-\d{4}(-\d{2}-\d{2})?$"#, options: .regularExpression) == nil
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
    }

    func prepare(cwd: URL, readable: [URL]) async throws {
        self.readable = readable
        guard models.isEmpty, let (data, response) = try? await URLSession.shared.data(for: request("/models")),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let list = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["data"] as? [[String: Any]]
        else { return }
        let ids = Self.chatModels(list.compactMap { $0["id"] as? String })
        models = ids.map { ModelChoice(id: $0, name: $0.replacingOccurrences(of: "models/", with: "")) }
        if let preferred, ids.contains(preferred) { return }
        preferred = ids.first
    }

    func choose(model: String) async throws {
        preferred = model
    }

    func cancel() {
        live?.cancel()
    }

    func shutdown() {
        live?.cancel()
    }

    static var tools: [[String: Any]] {
        Tool.all.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] }
    }

    func send(_ prompt: String, file: URL?, base doc: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws {
        if key == nil, !AgentSpec.named(id).keys.isEmpty { throw AgentError(message: "Add your \(AgentSpec.named(id).name) key in Settings.") }
        if models.isEmpty { try await prepare(cwd: URL(fileURLWithPath: NSHomeDirectory()), readable: readable) }
        guard let model = preferred else { throw AgentError(message: "\(AgentSpec.named(id).name) didn't list any models. Check the key.") }
        var text = prompt
        if let previous { text = "Earlier in this session:\n\(previous)\n\n" + text }
        var messages: [[String: Any]] = [["role": "system", "content": Tool.system], ["role": "user", "content": text]]
        let toolbox = Toolbox(doc: doc, readable: readable, events: events)
        var reply = ""
        events(.activity("Thinking"))
        for _ in 0..<12 {
            var body: [String: Any] = ["model": model, "stream": true, "messages": messages, "tools": Self.tools]
            if effort { body["reasoning_effort"] = "low" }
            var request = request("/chat/completions")
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            live = bytes.task
            defer { live = nil }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                var raw = ""
                for try await line in bytes.lines { raw += line }
                let json = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
                let message = (json?["error"] as? [String: Any])?["message"] as? String ?? json?["message"] as? String
                throw AgentError(message: status == 401 ? "That API key didn't work." : message.map(friendly) ?? "The API returned \(status).")
            }
            var said = ""
            var calls: [Int: (id: String, name: String, arguments: String)] = [:]
            var finish: String?
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
                if let error = event["error"] as? [String: Any] {
                    throw AgentError(message: (error["message"] as? String).map(friendly) ?? "The API hit an error.")
                }
                guard let choice = (event["choices"] as? [[String: Any]])?.first else { continue }
                finish = choice["finish_reason"] as? String ?? finish
                let delta = choice["delta"] as? [String: Any] ?? [:]
                if let t = delta["content"] as? String, !t.isEmpty {
                    said += t
                    reply += t
                    events(.text(t))
                }
                for call in delta["tool_calls"] as? [[String: Any]] ?? [] {
                    let index = call["index"] as? Int ?? 0
                    let function = call["function"] as? [String: Any] ?? [:]
                    if calls[index] == nil {
                        let name = function["name"] as? String ?? ""
                        calls[index] = (call["id"] as? String ?? "call_\(index)", name, "")
                        toolbox.start(index, name)
                    }
                    if let chunk = function["arguments"] as? String, !chunk.isEmpty {
                        calls[index]?.arguments += chunk
                        toolbox.feed(index, chunk)
                    }
                }
            }
            if finish == "length" { throw AgentError(message: "The answer ran past its length limit. Ask for a smaller change.") }
            var results: [[String: Any]] = []
            var again = false
            for index in calls.keys.sorted() {
                guard let done = toolbox.finish(index), let call = calls[index] else { continue }
                results.append(["role": "tool", "tool_call_id": call.id, "content": done.result.result])
                again = again || done.result.again
            }
            guard !calls.isEmpty, again else {
                let lines = prompt.components(separatedBy: "\n")
                let asked = lines.firstIndex { $0.hasSuffix("They just said:") }.flatMap { lines.indices.contains($0 + 2) ? lines[$0 + 2] : nil }
                previous = "They said: \(asked ?? "")\nYou replied: \(reply)"
                return
            }
            messages.append([
                "role": "assistant", "content": said.isEmpty ? NSNull() : said,
                "tool_calls": calls.keys.sorted().compactMap { calls[$0] }.map {
                    ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments.isEmpty ? "{}" : $0.arguments]]
                },
            ])
            messages += results
        }
        throw AgentError(message: "That took too many steps. Try a narrower request.")
    }
}

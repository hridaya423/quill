import Foundation
import QuillCore

struct TurnRecord: Codable {
    var id: String
    var at: Date
    var note: String
    var request: String
    var mode: String
    var agent: String
    var held: [String]
    var retried: Bool
    var exchanges: [Exchange]
}

struct EventRecord: Codable {
    var at: Date
    var event: String
    var turn: String?
    var detail: String?
}

enum Ledger {
    static let dir: URL = {
        let d = ProcessInfo.processInfo.environment["QUILL_SUPPORT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Quill")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static let turns = dir.appending(path: "turns.jsonl")
    static let events = dir.appending(path: "events.jsonl")

    static func append<T: Encodable>(_ value: T, to file: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(value) else { return }
        data.append(0x0A)
        if let h = try? FileHandle(forWritingTo: file) {
            _ = try? h.seekToEnd()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: file)
        }
    }

    static func read<T: Decodable>(_ type: T.Type, from file: URL) -> [T] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? decoder.decode(T.self, from: Data($0.utf8)) }
    }

    static func event(_ name: String, turn: String? = nil, detail: String? = nil) {
        append(EventRecord(at: .now, event: name, turn: turn, detail: detail), to: events)
    }
}

@MainActor
final class VoiceKeeper {
    static let every = 5
    let vault: URL
    var spec: AgentSpec
    private var distilling = false

    init(vault: URL, spec: AgentSpec) {
        self.vault = vault
        self.spec = spec
    }

    var url: URL { vault.appending(path: "Voice.md") }

    var notes: String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return [VoiceSection.mine, .learned, .measured].compactMap { s in
            section(s, in: text).map { "## \(s.rawValue)\n\($0)" }
        }.joined(separator: "\n\n")
    }

    nonisolated static func corpus(_ folders: [URL]) -> [String] {
        folders.flatMap { folder in
            (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])?
                .compactMap { $0 as? URL } ?? [])
                .filter { $0.pathExtension.lowercased() == "md" && !$0.lastPathComponent.contains("excalidraw") && $0.lastPathComponent != "Voice.md" }
                .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
    }

    func measure(_ folders: [URL]) async -> Fingerprint {
        let found = await Task.detached { fingerprint(Self.corpus(folders)) }.value
        let notes = folders.count == 1 ? "1 folder" : "\(folders.count) folders"
        let existing = try? String(contentsOf: url, encoding: .utf8)
        if found.words >= 150 {
            let source = "Measured from \(found.words.formatted()) words in \(notes) on \(Date.now.formatted(date: .abbreviated, time: .omitted))."
            try? voiceDocument(existing: existing, measured: describe(found), source: source).write(to: url, atomically: true, encoding: .utf8)
        } else if existing == nil {
            try? voiceDocument(existing: nil).write(to: url, atomically: true, encoding: .utf8)
        }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "measuredAt")
        return found
    }

    func distillIfDue() {
        let records = Ledger.read(TurnRecord.self, from: Ledger.turns)
        let done = UserDefaults.standard.integer(forKey: "distilledThrough")
        guard !distilling, records.count - done >= Self.every else { return }
        let recent = records.suffix(40).flatMap(\.exchanges)
        guard !recent.isEmpty else { return }
        distilling = true
        let voice = (try? String(contentsOf: url, encoding: .utf8)) ?? voiceDocument(existing: nil)
        let body = distillPrompt(voice: voice, exchanges: recent)
        let agent = spec.make()
        let cwd = Ledger.dir.appending(path: "distill")
        try? FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        Task {
            defer {
                agent.shutdown()
                distilling = false
            }
            var reply = ""
            do {
                try await agent.prepare(cwd: cwd)
                try await agent.send(body, base: "") { event in
                    if case .text(let t) = event { reply += t }
                }
            } catch {
                Ledger.event("distill-failed", detail: error.localizedDescription)
                return
            }
            guard let rules = learnedRules(from: reply) else { return }
            let current = (try? String(contentsOf: url, encoding: .utf8)) ?? voice
            try? voiceDocument(existing: current, learned: rules).write(to: url, atomically: true, encoding: .utf8)
            UserDefaults.standard.set(records.count, forKey: "distilledThrough")
            Ledger.event("distilled", detail: "\(recent.count) exchanges")
        }
    }
}

enum Floor {
    static let text: String = {
        let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/skills/prose")
        let skill = try? String(contentsOf: root.appending(path: "SKILL.md"), encoding: .utf8)
        let refs = ["tell-catalog.md", "anti-slop.md", "craft.md"].compactMap {
            try? String(contentsOf: root.appending(path: "references/\($0)"), encoding: .utf8)
        }
        return editorialFloor(skill: skill, references: refs)
    }()
}

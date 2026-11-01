import AppKit
import Foundation
import Testing
import QuillCore
@testable import Quill

struct Arm: Codable {
    var source: String
    var original: String
    var request: String
    var quill: String
    var generic: String
    var held: [String]
    var retried: Bool
}

@MainActor
struct Live {
    nonisolated static let out = ProcessInfo.processInfo.environment["QUILL_LIVE"]
    nonisolated static let corpus = ProcessInfo.processInfo.environment["QUILL_CORPUS"]

    static func paragraphs(_ root: URL, count: Int) -> [(String, String)] {
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "md" && !$0.path.contains("/Journal/") && !$0.path.contains("VISA") && !$0.path.contains("Flashcards") && !$0.lastPathComponent.contains("excalidraw") }
            .sorted { $0.path < $1.path }
        var found: [(String, String)] = []
        for f in files {
            guard let text = try? String(contentsOf: f, encoding: .utf8), isWriting(text) else { continue }
            let blocks = prose(from: text, lists: false).components(separatedBy: "\n\n").map {
                $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            }
            let lines = prose(from: text).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            for p in blocks + lines {
                let words = p.split(separator: " ").count
                if (20...110).contains(words), sentences(in: p).count >= 2, !p.contains("|"), !p.contains("http"), !found.contains(where: { $0.1 == p }) {
                    found.append((f.lastPathComponent, p))
                    break
                }
            }
        }
        var rng = SystemRandomNumberGenerator()
        return Array(found.shuffled(using: &rng).prefix(count))
    }

    static func generic(_ paragraph: String, _ request: String) async throws -> String {
        let agent = AgentSpec.named("claude").make()
        let cwd = FileManager.default.temporaryDirectory.appending(path: "quill-generic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        defer { agent.shutdown() }
        try await agent.prepare(cwd: cwd, readable: [])
        var reply = ""
        try await agent.send("\(request):\n\n\(paragraph)\n\nReply with only the edited paragraph. Do not edit files.", file: nil, base: "") { e in
            if case .text(let t) = e { reply += t }
        }
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test(.enabled(if: out != nil && corpus != nil), .timeLimit(.minutes(30)))
    func blindRun() async throws {
        let dir = URL(fileURLWithPath: Self.out!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let picked = Self.paragraphs(URL(fileURLWithPath: Self.corpus!), count: 10)
        Swift.print("paragraphs \(picked.count)")
        let vault = dir.appending(path: "vault")
        try? FileManager.default.removeItem(at: vault)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        Prefs.voiceSources = [Self.corpus!]
        for (i, (_, p)) in picked.enumerated() {
            try "\(p)\n".write(to: vault.appending(path: "p\(i).md"), atomically: true, encoding: .utf8)
        }
        let ws = Workspace(vault: vault)
        let (scroll, view) = QuillTextView.make()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        let choreographer = Choreographer(view: view)
        choreographer.onFinish = { [weak ws] n in ws?.finishedPlaying(n) }
        ws.editor = view
        ws.choreographer = choreographer
        view.onEdit = { [weak ws] in ws?.edited() }
        ws.start()
        let print = await ws.measure()
        try JSONEncoder().encode(print).write(to: dir.appending(path: "fingerprint.json"))
        try? FileManager.default.copyItem(at: vault.appending(path: "Voice.md"), to: dir.appending(path: "Voice.md"))

        let requests = ["Tighten this so it reads well", "Make this clearer"]
        var arms: [Arm] = []
        var held: [String] = []
        for (i, (source, p)) in picked.enumerated() {
            for (r, request) in requests.enumerated() {
                let url = vault.appending(path: "p\(i)-\(r).md")
                ws.open(vault.appending(path: "Voice.md"))
                try "\(p)\n".write(to: url, atomically: true, encoding: .utf8)
                ws.open(url)
                let before = (try? String(contentsOf: Ledger.events, encoding: .utf8)) ?? ""
                ws.ask(request)
                while true {
                    try await Task.sleep(for: .milliseconds(200))
                    if case .thinking = ws.phase { continue }
                    if case .applying = ws.phase { continue }
                    break
                }
                choreographer.land()
                let after = (try? String(contentsOf: Ledger.events, encoding: .utf8)) ?? ""
                let newHeld = after.dropFirst(before.count).split(separator: "\n").filter { $0.contains("\"held\"") }.map(String.init)
                held += newHeld
                let edited = view.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if r == 0 {
                    let g = try await Self.generic(p, request)
                    arms.append(Arm(source: source, original: p, request: request, quill: edited, generic: g, held: newHeld, retried: !newHeld.isEmpty))
                } else {
                    arms.append(Arm(source: source, original: p, request: request, quill: edited, generic: "", held: newHeld, retried: !newHeld.isEmpty))
                }
                Swift.print("turn \(i).\(r) phase \(ws.phase) held \(newHeld.count)")
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(arms).write(to: dir.appending(path: "arms.json"))
        let quillOut = arms.map(\.quill), genericOut = arms.filter { !$0.generic.isEmpty }.map(\.generic)
        let tq = quillOut.flatMap { tells(in: $0) }, tg = genericOut.flatMap { tells(in: $0) }
        let introduced = arms.flatMap { introducedTells(before: $0.original, after: $0.quill) }
        let fq = fingerprint(arms.filter { $0.request == requests[0] }.map(\.quill)), fg = fingerprint(genericOut)
        let report = """
        turns: \(arms.count)
        held proposals (pre-gate tell hits): \(held.count)
        tells introduced in shown Quill text: \(introduced.count) \(introduced.map(\.phrase))
        tells anywhere in Quill output (includes the writer's own): \(tq.count) \(tq.map(\.phrase))
        tells in generic output: \(tg.count) \(tg.map(\.phrase))
        distance to writer, Quill: \(String(format: "%.2f", distance(print, fq)))
        distance to writer, generic: \(String(format: "%.2f", distance(print, fg)))
        distance to writer, unedited originals: \(String(format: "%.2f", distance(print, fingerprint(picked.map(\.1)))))
        """
        try report.write(to: dir.appending(path: "report.txt"), atomically: true, encoding: .utf8)
        Swift.print(report)
        Prefs.voiceSources = []
    }
}

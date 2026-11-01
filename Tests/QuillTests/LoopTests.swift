import AppKit
import Foundation
import Testing
import QuillCore
@testable import Quill

@MainActor
final class ScriptedAgent: Agent {
    let canEditFiles = true
    let conversation: String? = "scripted"
    let model: ModelChoice? = nil
    let models: [ModelChoice] = []
    var edits: [(String) -> String]
    var reply = "Tightened the opening."
    var prompts: [String] = []

    init(_ edits: [(String) -> String]) {
        self.edits = edits
    }

    func prepare(cwd: URL, readable: [URL]) async throws {}
    func choose(model: String) async throws {}
    func cancel() {}
    func shutdown() {}

    func send(_ prompt: String, file: URL?, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws {
        prompts.append(prompt)
        guard let file, !edits.isEmpty else { return }
        let edit = edits.removeFirst()
        let text = try String(contentsOf: file, encoding: .utf8)
        try edit(text).write(to: file, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(200))
        events(.text(reply))
    }
}

@MainActor
@Suite(.serialized)
struct LoopTests {
    nonisolated static let support = ProcessInfo.processInfo.environment["QUILL_SUPPORT"]
    static var windows: [NSWindow] = []
    nonisolated static let original = "# Lumen\n\nWe are basically trying to kind of build a tool that maybe helps people write better, in a way.\n\nWriters lose hours to editing.\n"

    func setup(_ agent: ScriptedAgent) throws -> (Workspace, QuillTextView, URL) {
        #expect(Ledger.dir.path == Self.support)
        let vault = FileManager.default.temporaryDirectory.appending(path: "quill-loop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let note = vault.appending(path: "pitch.md")
        try Self.original.write(to: note, atomically: true, encoding: .utf8)
        let ws = Workspace(vault: vault)
        let (scroll, text) = QuillTextView.make()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        scroll.frame = window.contentView!.bounds
        Self.windows.append(window)
        ws.attach(text, Choreographer(view: text))
        ws.replace(agent)
        ws.start()
        ws.open(note)
        return (ws, text, note)
    }

    func settle(_ ws: Workspace) async {
        for _ in 0..<200 where ws.busy { try? await Task.sleep(for: .milliseconds(50)) }
        ws.choreographer?.land()
    }

    @Test(.enabled(if: support != nil)) func keptChangesReachTheVaultOnlyAfterReview() async throws {
        let agent = ScriptedAgent([{ $0.replacingOccurrences(of: "We are basically trying to kind of build a tool that maybe helps", with: "We build a tool that helps") }])
        let (ws, text, note) = try setup(agent)
        defer { ws.quit() }
        ws.ask("make the first sentence confident")
        await settle(ws)
        #expect(!ws.busy)
        #expect(text.string.contains("We build a tool that helps"))
        #expect(!ws.review.isEmpty)
        ws.flushSave()
        #expect(try String(contentsOf: note, encoding: .utf8) == Self.original)
        #expect(agent.prompts.first?.contains(Workspace.desk.path) == true)

        ws.keep()
        ws.flushSave()
        #expect(ws.review.isEmpty)
        #expect(try String(contentsOf: note, encoding: .utf8).contains("We build a tool that helps"))
        let record = Ledger.read(TurnRecord.self, from: Ledger.turns).last
        #expect(record?.request == "make the first sentence confident")
        #expect(record?.exchanges.allSatisfy { $0.outcome == .kept } == true)
    }

    @Test(.enabled(if: support != nil)) func oneUndoTakesBackAWholeTurn() async throws {
        let agent = ScriptedAgent([{ $0.replacingOccurrences(of: "basically ", with: "").replacingOccurrences(of: "maybe ", with: "").replacingOccurrences(of: ", in a way", with: "") }])
        let (ws, text, note) = try setup(agent)
        defer { ws.quit() }
        ws.ask("cut the hedges")
        await settle(ws)
        #expect(ws.review.hunks.count >= 2)
        text.undo(nil)
        #expect(text.string == Self.original)
        #expect(ws.review.isEmpty)
        text.redo(nil)
        #expect(!text.string.contains("basically"))
        #expect(!ws.review.isEmpty)
        ws.revert()
        ws.flushSave()
        #expect(text.string == Self.original)
        #expect(try String(contentsOf: note, encoding: .utf8) == Self.original)
    }

    @Test(.enabled(if: support != nil)) func typingDuringATurnSurvivesTheAgentsEdit() async throws {
        let agent = ScriptedAgent([{ $0.replacingOccurrences(of: "We are basically trying to kind of build", with: "We build") }])
        let (ws, text, _) = try setup(agent)
        defer { ws.quit() }
        ws.ask("tighten")
        let end = (text.string as NSString).length
        text.setSelectedRange(NSRange(location: end, length: 0))
        text.insertText("A line I typed.\n", replacementRange: text.selectedRange())
        await settle(ws)
        #expect(text.string.contains("We build a tool"))
        #expect(text.string.hasSuffix("A line I typed.\n"))
        #expect(ws.review.accepted(text.string) == Self.original + "A line I typed.\n")
    }

    @Test(.enabled(if: support != nil)) func heldEditIsRetriedThenFlagged() async throws {
        let bad: (String) -> String = { $0.replacingOccurrences(of: "We are basically trying to kind of build a tool", with: "We build more than a tool — not just an editor") }
        let agent = ScriptedAgent([bad, bad])
        let (ws, text, _) = try setup(agent)
        defer { ws.quit() }
        ws.ask("make it punchy")
        await settle(ws)
        #expect(agent.prompts.count == 2)
        #expect(agent.prompts.last?.contains("did not apply your last edit") == true)
        #expect(text.string.contains("not just an editor"))
        #expect(ws.review.hunks.contains { !$0.flags.isEmpty })
    }

    @Test(.enabled(if: support != nil)) func revertingOneChangeLeavesTheOther() async throws {
        let agent = ScriptedAgent([{ $0.replacingOccurrences(of: "basically trying to kind of build", with: "building").replacingOccurrences(of: "lose hours", with: "lose days") }])
        let (ws, text, note) = try setup(agent)
        defer { ws.quit() }
        ws.ask("tighten")
        await settle(ws)
        #expect(ws.review.hunks.count == 2)
        let first = ws.review.hunks[0]
        ws.revert([first])
        ws.keep()
        ws.flushSave()
        let saved = try String(contentsOf: note, encoding: .utf8)
        #expect(saved.contains("basically trying to kind of build"))
        #expect(saved.contains("lose days"))
        #expect(saved == text.string)
    }
}

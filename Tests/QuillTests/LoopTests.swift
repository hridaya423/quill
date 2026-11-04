import AppKit
import Foundation
import Testing
import QuillCore
@testable import Quill

@MainActor
class ScriptedAgent: Agent {
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

    func setup(_ agent: ScriptedAgent) async throws -> (Workspace, Page, URL) {
        #expect(Ledger.dir.path == Self.support)
        let vault = FileManager.default.temporaryDirectory.appending(path: "quill-loop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let note = vault.appending(path: "pitch.md")
        try Self.original.write(to: note, atomically: true, encoding: .utf8)
        let ws = Workspace(vault: vault)
        let text = Page()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = text
        Self.windows.append(window)
        for _ in 0..<200 where !text.ready { try await Task.sleep(for: .milliseconds(20)) }
        ws.attach(text)
        ws.replace(agent)
        ws.start()
        ws.open(note)
        return (ws, text, note)
    }

    func settle(_ ws: Workspace) async {
        for _ in 0..<200 where ws.busy { try? await Task.sleep(for: .milliseconds(50)) }
        await ws.editor?.settled()
        try? await Task.sleep(for: .milliseconds(50))
    }

    func until(_ done: () -> Bool) async {
        for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(done())
    }

    @Test(.enabled(if: support != nil && ProcessInfo.processInfo.environment["QUILL_CREW"] != nil), .timeLimit(.minutes(8)))
    func liveCrewFillsAnOutlineFromALink() async throws {
        let outline = "# Event ideas\n\nBrief: https://lu.ma/dm9hcg5q\n\n## Ideas\n\n- Scent personality quiz at check-in\n  - Pros:\n  - Cons:\n-\n  - Pros:\n  - Cons:\n-\n  - Pros:\n  - Cons:\n"
        let (ws, text, note) = try await setup(ScriptedAgent([]))
        defer { ws.quit() }
        ws.agentID = "codex"
        ws.agentID = "claude"
        try outline.write(to: note, atomically: true, encoding: .utf8)
        ws.open(note)
        text.load(outline)
        ws.crew = ["codex"]
        defer { ws.crew = [] }
        ws.ask("fill in the ideas with pros and cons for this event")
        for _ in 0..<9000 where ws.busy { try? await Task.sleep(for: .milliseconds(50)) }
        await ws.editor?.settled()
        Swift.print("<<<\(text.text)>>>\nBY \(ws.review.hunks.map { ($0.by ?? "-") + ": " + $0.new.prefix(60) })\nPHASE \(ws.phase)")
        if case .said(let s) = ws.phase, s.contains("couldn't answer") {
            Swift.print("CREW MATE UNAVAILABLE: \(s)")
        } else {
            #expect(Set(ws.review.hunks.compactMap(\.by)).count == 2)
        }
        #expect(text.text.contains("- Scent personality quiz at check-in"))
    }

    @Test(.enabled(if: support != nil)) func aCrewMateThatFailsIsNamedInTheReply() async throws {
        final class Broke: ScriptedAgent {
            override func send(_ prompt: String, file: URL?, base: String, events: @escaping @MainActor (AgentEvent) -> Void) async throws {
                throw NSError(domain: "codex", code: 1, userInfo: [NSLocalizedDescriptionKey: "You’ve hit your usage limit. Upgrade to Pro"])
            }
        }
        let lead = ScriptedAgent([{ $0.replacingOccurrences(of: "Writers lose hours to editing.", with: "Writers lose hours to editing. Quill gives them back.") }])
        let (ws, _, _) = try await setup(lead)
        defer { ws.quit() }
        ws.crew = ["codex"]
        ws.mates["codex"] = Broke([])
        defer { ws.crew = [] }
        ws.ask("add a line")
        await settle(ws)
        guard case .said(let s) = ws.phase else {
            Issue.record("no reply: \(ws.phase)")
            return
        }
        #expect(s.hasSuffix("Codex couldn't answer: You’ve hit your usage limit."))
        #expect(ws.review.hunks.count == 1)
    }

    @Test(.enabled(if: support != nil)) func crewAnswersStackSignedUnderTheWritersOutline() async throws {
        let outline = "# Hackathon ideas\n\n- AR study buddy\n  - Pros: works offline\n  - Cons:\n-\n"
        let lead = ScriptedAgent([{ $0.replacingOccurrences(of: "\n-\n", with: "\n- Voice-first lecture notes\n  - Pros: hands-free\n") }])
        let mate = ScriptedAgent([{ $0.replacingOccurrences(of: "\n-\n", with: "\n- Peer-review marketplace\n  - Pros: network effects\n") }])
        let (ws, text, note) = try await setup(lead)
        defer { ws.quit() }
        try outline.write(to: note, atomically: true, encoding: .utf8)
        ws.open(note)
        text.load(outline)
        ws.crew = ["codex"]
        ws.mates["codex"] = mate
        defer { ws.crew = [] }
        ws.ask("fill in more ideas with pros and cons")
        await settle(ws)
        #expect(text.text.contains("- AR study buddy\n  - Pros: works offline"))
        #expect(text.text.contains("- Voice-first lecture notes"))
        #expect(text.text.contains("- Peer-review marketplace"))
        let by = Set(ws.review.hunks.compactMap(\.by))
        #expect(by == ["Claude Code", "Codex"])
        #expect(lead.prompts.first?.contains("Other co-writers (Codex)") == true)
        #expect(mate.prompts.first?.contains("Other co-writers (Claude Code)") == true)
        #expect(mate.prompts.first?.contains("fill those slots in place") == true)
    }

    @Test(.enabled(if: support != nil)) func keptChangesReachTheVaultOnlyAfterReview() async throws {
        let agent = ScriptedAgent([{ $0.replacingOccurrences(of: "We are basically trying to kind of build a tool that maybe helps", with: "We build a tool that helps") }])
        let (ws, text, note) = try await setup(agent)
        defer { ws.quit() }
        ws.ask("make the first sentence confident")
        await settle(ws)
        #expect(!ws.busy)
        #expect(text.text.contains("We build a tool that helps"))
        #expect(!ws.review.isEmpty)
        ws.flushSave()
        #expect(try String(contentsOf: note, encoding: .utf8) == Self.original)
        #expect(agent.prompts.first?.contains(ws.desk.path) == true)

        ws.keep()
        ws.flushSave()
        #expect(ws.review.isEmpty)
        #expect(try String(contentsOf: note, encoding: .utf8).contains("We build a tool that helps"))
        let record = Ledger.read(TurnRecord.self, from: Ledger.turns).last
        #expect(record?.request == "make the first sentence confident")
        #expect(record?.exchanges.allSatisfy { $0.outcome == .kept } == true)
    }

    @Test(.enabled(if: support != nil)) func keepAllSavesTheNoteWithoutAnotherEdit() async throws {
        let agent = ScriptedAgent([{ $0.replacingOccurrences(of: "We are basically trying to kind of build a tool that maybe helps", with: "We build a tool that helps") }])
        let (ws, _, note) = try await setup(agent)
        defer { ws.quit() }
        ws.ask("make the first sentence confident")
        await settle(ws)
        ws.keep()
        try await Task.sleep(for: .milliseconds(900))
        #expect(try String(contentsOf: note, encoding: .utf8).contains("We build a tool that helps"))
    }

    @Test(.enabled(if: support != nil)) func twoWindowsWithTheSameNoteNameNeverShareAWorkingCopy() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "quill-two-\(UUID().uuidString)")
        var opened: [(Workspace, Page, ScriptedAgent, URL)] = []
        for (name, phrase) in [("site", "SITE"), ("api", "API")] {
            let root = base.appending(path: name)
            let folder = root.appending(path: "docs")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let note = folder.appending(path: "architecture.md")
            try Self.original.write(to: note, atomically: true, encoding: .utf8)
            let agent = ScriptedAgent([{ $0.replacingOccurrences(of: "Writers lose hours", with: "\(phrase) writers lose hours") }])
            let ws = Workspace(vault: root, home: false)
            let text = Page()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = text
            Self.windows.append(window)
            for _ in 0..<200 where !text.ready { try await Task.sleep(for: .milliseconds(20)) }
            ws.attach(text)
            ws.replace(agent)
            ws.start()
            ws.open(note)
            opened.append((ws, text, agent, note))
        }
        defer { opened.forEach { $0.0.quit() } }
        for (ws, _, _, _) in opened { ws.ask("tighten it") }
        for (ws, _, _, _) in opened { await settle(ws) }
        let (site, api) = (opened[0], opened[1])
        #expect(site.1.text.contains("SITE writers lose hours") && !site.1.text.contains("API"))
        #expect(api.1.text.contains("API writers lose hours") && !api.1.text.contains("SITE"))
        #expect(site.0.desk != api.0.desk)
        let sitePrompt = try #require(site.2.prompts.first)
        #expect(sitePrompt.contains("The note lives in \(site.3.deletingLastPathComponent().path), inside \(base.appending(path: "site").path)"))
        #expect(sitePrompt.contains(site.0.desk.path))
        #expect(!sitePrompt.contains(api.0.desk.path))
    }

    @Test(.enabled(if: support != nil)) func oneUndoTakesBackAWholeTurn() async throws {
        let agent = ScriptedAgent([{ $0.replacingOccurrences(of: "basically ", with: "").replacingOccurrences(of: "maybe ", with: "").replacingOccurrences(of: ", in a way", with: "") }])
        let (ws, text, note) = try await setup(agent)
        defer { ws.quit() }
        ws.ask("cut the hedges")
        await settle(ws)
        #expect(ws.review.hunks.count >= 2)
        text.undo(nil)
        await until { text.text == Self.original }
        #expect(ws.review.isEmpty)
        text.redo(nil)
        await until { !text.text.contains("basically") }
        #expect(!ws.review.isEmpty)
        ws.revert()
        await until { text.text == Self.original }
        ws.flushSave()
        #expect(text.text == Self.original)
        #expect(try String(contentsOf: note, encoding: .utf8) == Self.original)
    }

    @Test(.enabled(if: support != nil)) func typingDuringATurnSurvivesTheAgentsEdit() async throws {
        let agent = ScriptedAgent([{ $0.replacingOccurrences(of: "We are basically trying to kind of build", with: "We build") }])
        let (ws, text, _) = try await setup(agent)
        defer { ws.quit() }
        ws.ask("tighten")
        let end = text.buffer.length
        _ = try await text.evaluateJavaScript("quill.view.dispatch({changes: {from: \(end), insert: 'A line I typed.\\n'}, userEvent: 'input.type'})")
        await settle(ws)
        #expect(text.text.contains("We build a tool"))
        #expect(text.text.hasSuffix("A line I typed.\n"))
        #expect(ws.review.accepted(text.text) == Self.original + "A line I typed.\n")
    }

    @Test(.enabled(if: support != nil)) func heldEditIsRetriedThenFlagged() async throws {
        let bad: (String) -> String = { $0.replacingOccurrences(of: "We are basically trying to kind of build a tool", with: "We build more than a tool — not just an editor") }
        let agent = ScriptedAgent([bad, bad])
        let (ws, text, _) = try await setup(agent)
        defer { ws.quit() }
        ws.ask("make it punchy")
        await settle(ws)
        #expect(agent.prompts.count == 2)
        #expect(agent.prompts.last?.contains("did not apply your last edit") == true)
        #expect(text.text.contains("not just an editor"))
        #expect(ws.review.hunks.contains { !$0.flags.isEmpty })
    }

    @Test(.enabled(if: support != nil)) func revertingOneChangeLeavesTheOther() async throws {
        let agent = ScriptedAgent([{ $0.replacingOccurrences(of: "basically trying to kind of build", with: "building").replacingOccurrences(of: "lose hours", with: "lose days") }])
        let (ws, text, note) = try await setup(agent)
        defer { ws.quit() }
        ws.ask("tighten")
        await settle(ws)
        #expect(ws.review.hunks.count == 2)
        let first = ws.review.hunks[0]
        ws.revert([first])
        await until { text.text.contains("basically trying to kind of build") }
        ws.keep()
        ws.flushSave()
        let saved = try String(contentsOf: note, encoding: .utf8)
        #expect(saved.contains("basically trying to kind of build"))
        #expect(saved.contains("lose days"))
        #expect(saved == text.text)
    }
}

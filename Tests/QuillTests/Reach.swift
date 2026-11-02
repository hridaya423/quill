import Foundation
import Testing
import QuillCore
@testable import Quill

@MainActor
struct Reach {
    nonisolated static let agents = ProcessInfo.processInfo.environment["QUILL_REACH"]

    @Test(.enabled(if: agents != nil), .timeLimit(.minutes(10)))
    func draftsFromAFolderTheWriterNames() async throws {
        for id in Self.agents!.split(separator: ",").map(String.init) {
            let desk = FileManager.default.temporaryDirectory.appending(path: "quill-reach-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: desk, withIntermediateDirectories: true)
            let file = desk.appending(path: "Pitch.md")
            let base = "# Demo video pitch\n\n"
            try base.write(to: file, atomically: true, encoding: .utf8)
            let agent = AgentSpec.named(id).make()
            defer { agent.shutdown() }
            try await agent.prepare(cwd: desk, readable: [])
            let request = Request(words: "go into Honey/edvideo and draft a demo video pitch", title: "Pitch", path: file.path, text: base, selection: nil, mode: .guided)
            var reply = ""
            var steps: [String] = []
            try await agent.send(prompt(request, canEditFiles: agent.canEditFiles, briefing: Guide.briefing()), file: file, base: base) { e in
                switch e {
                case .text(let t): reply += t
                case .activity(let a): if steps.last != a { steps.append(a) }
                case .proposed(let next): try? next.write(to: file, atomically: true, encoding: .utf8)
                default: break
                }
            }
            let draft = try String(contentsOf: file, encoding: .utf8)
            Swift.print("[\(id)] steps: \(steps.joined(separator: " → "))\n[\(id)] reply: \(readable(reply))\n[\(id)] draft:\n\(draft)\n")
            #expect(draft.count > base.count + 200, "\(id) wrote no draft")
            #expect(draft.contains("LiveFrame"), "\(id) did not ground the draft in the folder")
        }
    }
}

@Test func coWritersReadTheHomeFolderButNotItsSecrets() {
    let home = NSHomeDirectory()
    #expect(permits(kind: "read", paths: ["\(home)/Honey/edvideo/README.md"], file: nil, readable: []))
    #expect(permits(kind: "search", paths: [], file: nil, readable: []))
    #expect(!permits(kind: "read", paths: ["\(home)/.ssh/id_ed25519"], file: nil, readable: []))
    #expect(!permits(kind: "read", paths: ["\(home)/.config/envsync/vault.env.age"], file: nil, readable: []))
    #expect(!permits(kind: "read", paths: ["\(home)/Library/Keychains/login.keychain-db"], file: nil, readable: []))
    #expect(!permits(kind: "read", paths: ["/etc/master.passwd"], file: nil, readable: []))
    #expect(permits(kind: "read", paths: ["\(home)/.agents/skills/prose/SKILL.md"], file: nil, readable: [URL(fileURLWithPath: "\(home)/.agents/skills/prose")]))
    #expect(!permits(kind: "edit", paths: ["\(home)/Honey/edvideo/README.md"], file: URL(fileURLWithPath: "/tmp/desk/Pitch.md"), readable: []))
    #expect(!permits(kind: "execute", paths: [], file: nil, readable: []))
}

@Test func pathsTheWriterNamesResolveFromHome() {
    let home = NSHomeDirectory()
    #expect(located("Honey/edvideo").path == "\(home)/Honey/edvideo")
    #expect(located("~/Honey").path == "\(home)/Honey")
    #expect(located("/tmp").path == "/tmp")
}

@MainActor @Test func onlyChatModelsAreOffered() {
    let offered = ChatAgent.chatModels(["gpt-5.2", "gpt-5.2-2025-12-11", "gpt-4o-mini-tts", "text-embedding-3-large", "whisper-1", "gpt-5.1-codex", "o3-pro", "gpt-5-mini", "mistral-large-2411", "openai/gpt-oss-120b"])
    #expect(offered == ["openai/gpt-oss-120b", "gpt-5.2", "gpt-5-mini"])
}

@Test func pastedAPIURLsNormalize() {
    let before = Prefs.store.string(forKey: "endpoint")
    defer { Prefs.store.set(before, forKey: "endpoint") }
    Prefs.endpoint = "https://api.openai.com/"
    #expect(Prefs.endpoint == "https://api.openai.com/v1")
    Prefs.endpoint = " https://openrouter.ai/api/v1/ "
    #expect(Prefs.endpoint == "https://openrouter.ai/api/v1")
    Prefs.endpoint = "http://localhost:11434"
    #expect(Prefs.endpoint == "http://localhost:11434/v1")
    Prefs.endpoint = "https://api.anthropic.com"
    #expect(Prefs.endpoint == "https://api.anthropic.com/v1")
}

@Test func theProseGuideShipsInsideQuill() throws {
    let bundled = try #require(Brand.url("Prose"))
    #expect(FileManager.default.fileExists(atPath: bundled.appending(path: "SKILL.md").path))
    #expect(FileManager.default.fileExists(atPath: bundled.appending(path: "references/tell-catalog.md").path))
    #expect(Guide.briefing().contains("# Prose"))
}

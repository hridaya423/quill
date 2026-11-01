import Foundation
import Testing
@testable import QuillCore

@Test func catalogTellsAreCaught() {
    let kinds = Set(tells(in: "Let's delve into it — this isn't just a tool, but a habit. In order to win, we must foster growth and enhance trust.").map(\.kind))
    #expect(kinds.isSuperset(of: ["AI vocabulary", "Em dash", "Negative parallelism", "Filler", "AI vocabulary cluster"]))
}

@Test func chatbotAndContractionEdges() {
    #expect(tells(in: "Certainly! Here it is.").map(\.kind) == ["Chatbot artifact"])
    #expect(tells(in: "It isn’t only fast, but cheap.").map(\.kind) == ["Negative parallelism"])
    #expect(tells(in: "I want just a bit more time, but fine.").isEmpty)
}

@Test func plainWritingIsClean() {
    let mine = "i just want this to work. the server keeps dying at 3am and I don't know why, but I think it's the cron job. not sure, but it's worth a look tomorrow."
    #expect(tells(in: mine).isEmpty)
}

@Test func onlyIntroducedTellsCount() {
    let before = "I ship fast — sometimes too fast."
    #expect(introducedTells(before: before, after: "I ship fast — sometimes too fast, and I fix it later.").isEmpty)
    #expect(introducedTells(before: before, after: "I ship fast. Let's delve into why.").map(\.kind) == ["AI vocabulary"])
    #expect(introducedTells(before: "a", after: "b — c", allowEmDash: true).isEmpty)
}

@Test func changedParagraphsIsolateTheEdit() {
    let (a, b) = changedParagraphs(base: "one\n\ntwo\n\nthree", proposed: "one\n\nTWO\n\nthree")
    #expect(a == "two")
    #expect(b == "TWO")
}

@Test func fingerprintMeasuresVoice() {
    let casual = fingerprint(["i don't really know. it's fine, honestly. I'm gonna ship it anyway and see what breaks!"])
    let formal = fingerprint(["Moreover, the system utilizes a comprehensive approach. Therefore, it facilitates robust outcomes for every stakeholder involved in the process."])
    #expect(casual.contractions > 20)
    #expect(casual.lowercaseStarts > 0.3)
    #expect(casual.habits["honestly"] != nil)
    #expect(formal.contractions == 0)
    #expect(casual.avoided.contains("moreover") && !formal.avoided.contains("moreover"))
    #expect(distance(casual, casual) == 0)
    #expect(distance(casual, formal) > distance(casual, fingerprint(["it's ok. i think it works, really."])))
}

@Test func proseStripsMarkdown() {
    #expect(prose(from: "---\ntags: x\n---\n# Title\n- **bold** [link](http://a.b) and [[Note|alias]]\n```\ncode\n```") == "bold link and alias")
}

@Test func exchangesClassifyWhatTheWriterKept() {
    let before = "# T\n\nwe are basically trying to build a tool.\n\nsecond para."
    let proposed = "# T\n\nWe build a tool.\n\nsecond para."
    #expect(exchanges(request: "r", before: before, proposed: proposed, kept: proposed).map(\.outcome) == [.kept])
    #expect(exchanges(request: "r", before: before, proposed: proposed, kept: before).map(\.outcome) == [.reverted])
    let hand = "# T\n\nwe build a tool for writers.\n\nsecond para."
    let e = exchanges(request: "r", before: before, proposed: proposed, kept: hand)
    #expect(e.map(\.outcome) == [.rewritten])
    #expect(e.first?.final == "we build a tool for writers.")
    #expect(e.first?.before == "we are basically trying to build a tool.")
}

@Test func voiceDocumentKeepsTheWritersSection() {
    let first = voiceDocument(existing: nil, measured: ["Sentences average 9 words."], source: "Measured from 3 notes.")
    #expect(section(.measured, in: first)?.contains("9 words") == true)
    let edited = first.replacingOccurrences(of: "- Add your own rules here. Quill treats them as yours and never edits them.", with: "- never use the word utilize")
    let next = voiceDocument(existing: edited, learned: "- Keep lowercase starts. Example: “so i built it”.")
    #expect(section(.mine, in: next) == "- never use the word utilize")
    #expect(section(.learned, in: next)?.hasPrefix("- Keep lowercase") == true)
    #expect(section(.measured, in: next)?.contains("9 words") == true)
    #expect(learnedRules(from: "Sure.\n- One. Example: “a”.\n- Two.") == "- One. Example: “a”.\n- Two.")
}

@Test func drawingsAreNotWriting() {
    let drawing = "---\nexcalidraw-plugin: parsed\n---\n==⚠  Switch to EXCALIDRAW VIEW ==\nYou can decompress Drawing data with the command palette. For more info check plugin settings."
    #expect(!isWriting(drawing))
    #expect(fingerprint([drawing]).words == 0)
}

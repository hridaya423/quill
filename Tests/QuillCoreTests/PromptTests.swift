import Foundation
import Testing
@testable import QuillCore

let pitch = "# Lumen\n\nWe are basically trying to build a tool.\n\nWriters lose hours to editing."

@Test func notesAnchorToExactQuotes() {
    let reply = """
    Sure:
    [{"quote": "Writers lose hours to editing", "note": "Strong. Lead with this."},
     {"quote": "we are basically trying", "note": "Hedging; cut it."},
     {"quote": "not in the doc at all", "note": "dropped"}]
    """
    let n = notes(from: reply, in: pitch)
    #expect(n?.count == 2)
    #expect(n?.first?.quote == "we are basically trying")
    #expect((pitch as NSString).substring(with: n![0].range) == "We are basically trying")
}

@Test func plainReplyIsNotNotes() {
    #expect(notes(from: "Looks good to me.", in: pitch) == nil)
}

@Test func promptCarriesWordsDocumentAndMode() {
    let r = Request(words: "make the opening punchier", path: "/v/pitch.md", text: pitch, selection: nil, mode: .notes)
    let p = prompt(r, canEditFiles: true)
    #expect(p.contains("make the opening punchier"))
    #expect(p.contains(pitch))
    #expect(p.contains("JSON array"))
    #expect(!prompt(Request(words: "x", path: "/p", text: "t", selection: "sel", mode: .guided), canEditFiles: false).contains("JSON array"))
}

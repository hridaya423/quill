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
    let r = Request(words: "make the opening punchier", title: "pitch", path: "/desk/pitch.md", text: pitch, selection: nil, mode: .notes)
    let p = prompt(r, canEditFiles: true, voice: "## My rules\n- lowercase")
    #expect(p.contains("make the opening punchier"))
    #expect(p.contains(pitch))
    #expect(p.contains("<notes>"))
    #expect(p.contains("/desk/pitch.md"))
    #expect(p.contains("follow the voice notes"))
    #expect(!prompt(Request(words: "x", title: "t", path: "/p", text: "t", selection: "sel", mode: .guided), canEditFiles: false).contains("<notes>"))
}

@Test func taggedNotesIgnoreBracketsInTheReply() {
    let reply = """
    Two thoughts [roughly]:
    <notes>[{"quote": "Writers lose hours to editing", "lens": "order", "note": "Lead with this."}]</notes>
    """
    let n = notes(from: reply, in: pitch)
    #expect(n?.count == 1)
    #expect(n?.first?.lens == "Order")
}

@Test func mentionsAreTheTrailingAtToken() {
    #expect(mentionToken("draft a pitch from @Honey/ed") == "Honey/ed")
    #expect(mentionToken("@") == "")
    #expect(mentionToken("mail me at sam@site") == nil)
    #expect(mentionToken("from @Honey/edvideo/ and more") == nil)
    #expect(mentionToken("no mention") == nil)
}

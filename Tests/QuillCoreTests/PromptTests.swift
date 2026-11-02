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

@Test func streamingNotesNeverShowAsText() {
    #expect(readable(#"<notes>[{"quote": "You already know your writing"#) == "")
    #expect(readable(#"Here goes. <notes>[{"quote": "a", "note": "b"}"#) == "Here goes.")
    #expect(readable(#"[{"quote": "You already know", "lens": "Cut", "note": "Cut it."}]"#) == "")
    #expect(readable("<quote>You already know</quote> reads flat.") == "You already know reads flat.")
    #expect(readable("Done. <not") == "Done.")
}

@Test func repliesStayCrisp() {
    let edit = """
    I rewrote the pitch sentence in "Try it" as "We build a tool that helps people write better." I cut the hedges "basically", "trying to", "kind of", "maybe" and "in a way."

    I read your request as the exercise that section sets up. If you meant the note's first sentence, say so.
    """
    #expect(crisp(edit, sentences: 1) == #"I rewrote the pitch sentence in "Try it" as "We build a tool that helps people write better.""#)
    #expect(crisp("Strong opening. The middle drags. Cut the second list. End on the image. Done.", sentences: 3) == "Strong opening. The middle drags. Cut the second list.")
    #expect(crisp("Short.", sentences: 3) == "Short.")
}

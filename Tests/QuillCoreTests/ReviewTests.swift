import Foundation
import Testing
@testable import QuillCore

private struct Doc {
    var text: NSMutableString
    var review = Review()

    init(_ s: String) { text = NSMutableString(string: s) }

    mutating func agent(_ find: String, _ replace: String, turn: Int = 1, flags: [String] = []) {
        let r = text.range(of: find)
        let before = NSString(string: text as String)
        text.replaceCharacters(in: r, with: replace)
        review.agent(r, before: before, after: NSString(string: text as String), turn: turn, flags: flags)
    }

    mutating func type(_ r: NSRange, _ s: String) -> [Hunk] {
        text.replaceCharacters(in: r, with: s)
        return review.user(r, length: (s as NSString).length)
    }

    func shown(_ h: Hunk) -> String { text.substring(with: h.range) }
    var string: String { text as String }
}

@Test func agentEditIsPendingAndTheVaultKeepsTheOriginal() {
    var d = Doc("We are basically building a tool.")
    d.agent("basically building", "building")
    #expect(d.review.hunks.count == 1)
    let h = d.review.hunks[0]
    #expect(h.old == "basically building")
    #expect(h.new == "building")
    #expect(d.shown(h) == "building")
    #expect(d.review.accepted(d.string) == "We are basically building a tool.")
}

@Test func typingBeforeAChangeShiftsIt() {
    var d = Doc("We are basically building a tool.")
    d.agent("basically building", "building")
    #expect(d.type(NSRange(location: 0, length: 0), "Hi. ").isEmpty)
    #expect(d.shown(d.review.hunks[0]) == "building")
    #expect(d.review.accepted(d.string) == "Hi. We are basically building a tool.")
}

@Test func typingAtTheStartOfAChangeStaysOutsideIt() {
    var d = Doc("We are basically building a tool.")
    d.agent("basically building", "building")
    let start = d.review.hunks[0].range.location
    _ = d.type(NSRange(location: start, length: 0), "now ")
    #expect(d.shown(d.review.hunks[0]) == "building")
    #expect(d.review.hunks[0].touched == false)
}

@Test func typingInsideAChangeMarksItRewritten() {
    var d = Doc("We are basically building a tool.")
    d.agent("basically building", "building")
    let h = d.review.hunks[0]
    #expect(d.type(NSRange(location: h.range.location + 5, length: 0), "-")
        .isEmpty)
    #expect(d.review.hunks[0].touched)
    #expect(d.shown(d.review.hunks[0]) == "build-ing")
    #expect(d.review.accepted(d.string) == "We are basically building a tool.")
}

@Test func editingAcrossTheEdgeOfAChangeResolvesIt() {
    var d = Doc("We are basically building a tool.")
    d.agent("basically building", "building")
    let h = d.review.hunks[0]
    let crossed = d.type(NSRange(location: NSMaxRange(h.range) - 3, length: 6), "")
    #expect(crossed.map(\.id) == [h.id])
    #expect(d.review.isEmpty)
}

@Test func laterAgentEditMergesAndRemembersTheOriginal() {
    var d = Doc("We are basically building a tool.")
    d.agent("basically building", "building")
    d.agent("building a", "making a", turn: 2)
    #expect(d.review.hunks.count == 1)
    let h = d.review.hunks[0]
    #expect(h.old == "basically building a")
    #expect(h.turn == 2)
    #expect(d.review.accepted(d.string) == "We are basically building a tool.")
}

@Test func agentRestoringTheOriginalLeavesNothingToReview() {
    var d = Doc("We are basically building a tool.")
    d.agent("basically building", "building")
    d.agent("building", "basically building")
    #expect(d.review.isEmpty)
}

@Test func pureDeletionIsTrackedAndRestorable() {
    var d = Doc("We are basically building a tool.")
    d.agent(" basically", "")
    let h = d.review.hunks[0]
    #expect(h.range.length == 0)
    #expect(h.old == " basically")
    #expect(d.review.accepted(d.string) == "We are basically building a tool.")
}

@Test func revertingOneChangeShiftsTheOthers() {
    var d = Doc("One fine day. Two fine days.")
    d.agent("One fine", "A")
    d.agent("Two fine", "Several", turn: 1)
    #expect(d.review.hunks.count == 2)
    var r = d.review
    let first = r.remove(d.review.hunks[0].id)!
    d.review = r
    _ = d.type(first.range, first.old)
    #expect(d.string == "One fine day. Several days.")
    #expect(d.shown(d.review.hunks[0]) == "Several")
}

@Test func itemScannerYieldsEachCompletedEdit() {
    var s = ItemScanner()
    #expect(s.feed(#"{"edits": [{"find": "a \"}\" b", "repl"#) == nil)
    let one = s.feed(#"ace": "x"}, {"find": "c"#)
    #expect(one == #"{"edits": [{"find": "a \"}\" b", "replace": "x"}]}"#)
    #expect(s.feed(#"", "replace": "{d}"#) == nil)
    let two = s.feed(#""}]}"#)
    #expect(two == #"{"edits": [{"find": "a \"}\" b", "replace": "x"}, {"find": "c", "replace": "{d}"}]}"#)
    #expect(s.raw == #"{"edits": [{"find": "a \"}\" b", "replace": "x"}, {"find": "c", "replace": "{d}"}]}"#)
}

@Test func exchangeIsTheParagraphAroundTheChange() {
    var d = Doc("One two.\n\nThree four five.\n\nSix.")
    d.agent("four five", "5")
    let h = d.review.hunks[0]
    let e = exchange(h, request: "shorter", outcome: .kept, in: NSString(string: d.string), at: h.range)
    #expect(e.before == "Three four five.")
    #expect(e.proposed == "Three 5.")
    #expect(e.final == "Three 5.")
}

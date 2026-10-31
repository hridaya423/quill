import Foundation
import Testing
@testable import QuillCore

@Test func identicalTextHasNoChanges() {
    #expect(changes(from: "same words", to: "same words").isEmpty)
}

@Test func singleWordSwap() {
    #expect(changes(from: "hello world", to: "hey world") == [Change(range: NSRange(location: 0, length: 5), text: "hey")])
}

@Test func neighbouringWordsCoalesceIntoOneChange() {
    let c = changes(from: "a hello big world", to: "a hey small world")
    #expect(c == [Change(range: NSRange(location: 2, length: 9), text: "hey small")])
}

@Test func changesInSeparateParagraphsStaySeparate() {
    let c = changes(from: "one two\n\nthree four", to: "uno two\n\nthree cuatro")
    #expect(c.count == 2)
}

@Test func rangesAreUTF16() {
    let old = "café 👋 ok", new = "café 👋 fine"
    let c = changes(from: old, to: new)
    #expect(c.count == 1)
    #expect((old as NSString).substring(with: c[0].range) == "ok")
}

@Test func applyRoundTripsOnRealEdits() {
    let pairs = [
        ("We are basically trying to kind of build a tool that helps people maybe write better, in a way.",
         "Lumen helps people write better."),
        ("# Title\n\nFirst para.\n\nSecond para.", "# Better title\n\nFirst para, sharper.\n\nSecond para."),
        ("", "Fresh text."),
        ("Delete me entirely.", ""),
        ("Don't stop — it’s fine.", "Do not stop; it is fine!"),
    ]
    for (a, b) in pairs {
        #expect(apply(changes(from: a, to: b), to: a) == b)
    }
}

@Test func applyRoundTripsOnRandomMutations() {
    var rng = SplitMix(seed: 42)
    let words = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", ",", ".", "\n\n", "née", "🦊"]
    for _ in 0..<500 {
        let a = (0..<rng.next(30)).map { _ in words[rng.next(words.count)] }
        var b = a
        for _ in 0..<rng.next(6) {
            let k = rng.next(3)
            if k == 0, !b.isEmpty { b.remove(at: rng.next(b.count)) }
            else if k == 1 { b.insert(words[rng.next(words.count)], at: rng.next(b.count + 1)) }
            else if !b.isEmpty { b[rng.next(b.count)] = words[rng.next(words.count)] }
        }
        let sa = a.joined(separator: " "), sb = b.joined(separator: " ")
        #expect(apply(changes(from: sa, to: sb), to: sa) == sb)
    }
}

@Test func shiftedChangesApplyInReadingOrder() {
    let a = "one two three four", b = "uno two tres cuatro"
    let s = NSMutableString(string: a)
    for c in shifted(changes(from: a, to: b)) { s.replaceCharacters(in: c.range, with: c.text) }
    #expect(s as String == b)
}

@Test func mergeKeepsBothSidesWhenTheyTouchDifferentParagraphs() {
    let base = "Opening line here.\n\nSecond paragraph."
    let mine = "Opening line here.\n\nSecond paragraph, which I typed into."
    let theirs = "A sharper opening.\n\nSecond paragraph."
    let result = apply(merge(base: base, current: mine, proposed: theirs), to: mine)
    #expect(result == "A sharper opening.\n\nSecond paragraph, which I typed into.")
}

@Test func mergeDropsAgentChangesThatCollideWithTyping() {
    let base = "The cat sat."
    let mine = "The dog sat."
    let theirs = "The bird sat."
    #expect(merge(base: base, current: mine, proposed: theirs).isEmpty)
}

@Test func mergeShiftsAgentChangesPastEarlierTyping() {
    let base = "alpha beta gamma"
    let mine = "alpha alpha beta gamma"
    let theirs = "alpha beta delta"
    #expect(apply(merge(base: base, current: mine, proposed: theirs), to: mine) == "alpha alpha beta delta")
}

@Test func mergeWithNoTypingIsPlainDiff() {
    let base = "hello world"
    #expect(merge(base: base, current: base, proposed: "hey world") == changes(from: base, to: "hey world"))
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next(_ bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Int((z ^ (z >> 31)) % UInt64(bound))
    }
}

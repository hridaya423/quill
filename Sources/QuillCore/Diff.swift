import Foundation

public struct Change: Equatable, Sendable {
    public var range: NSRange
    public var text: String

    public init(range: NSRange, text: String) {
        self.range = range
        self.text = text
    }

    var delta: Int { text.utf16.count - range.length }
}

func tokenize(_ s: String) -> [Substring] {
    var tokens: [Substring] = []
    var start = s.startIndex
    var kind = 0
    for i in s.indices {
        let c = s[i]
        let k: Int
        if c.isNewline { k = 3 }
        else if c.isWhitespace { k = 1 }
        else if c.isLetter || c.isNumber || ((c == "'" || c == "’") && kind == 0) { k = 0 }
        else { k = 2 }
        if i != start && (k != kind || k >= 2) {
            tokens.append(s[start..<i])
            start = i
        }
        kind = k
    }
    if start != s.endIndex { tokens.append(s[start...]) }
    return tokens
}

public func changes(from old: String, to new: String) -> [Change] {
    if old == new { return [] }
    let a = tokenize(old), b = tokenize(new)
    let diff = b.difference(from: a)
    var removed = Set<Int>(), inserted = Set<Int>()
    for step in diff {
        switch step {
        case .remove(let offset, _, _): removed.insert(offset)
        case .insert(let offset, _, _): inserted.insert(offset)
        }
    }

    struct Hunk { var lo: Int; var hi: Int; var newLo: Int; var newHi: Int }
    var hunks: [Hunk] = []
    var i = 0, j = 0
    while i < a.count || j < b.count {
        if removed.contains(i) || inserted.contains(j) {
            var h = Hunk(lo: i, hi: i, newLo: j, newHi: j)
            while removed.contains(i) || inserted.contains(j) {
                if removed.contains(i) { i += 1 }
                if inserted.contains(j) { j += 1 }
            }
            h.hi = i
            h.newHi = j
            hunks.append(h)
        } else {
            i += 1
            j += 1
        }
    }

    func bridgeable(_ gap: ArraySlice<Substring>) -> Bool {
        let words = gap.filter { $0.first.map { !$0.isWhitespace } ?? false }
        if gap.contains(where: { $0.first?.isNewline == true }) { return false }
        return words.isEmpty || (words.count == 1 && words[0].count <= 3)
    }

    var merged: [Hunk] = []
    for h in hunks {
        if var last = merged.last, bridgeable(a[last.hi..<h.lo]) {
            last.hi = h.hi
            last.newHi = h.newHi
            merged[merged.count - 1] = last
        } else {
            merged.append(h)
        }
    }

    var offsets = [0]
    offsets.reserveCapacity(a.count + 1)
    for t in a { offsets.append(offsets.last! + t.utf16.count) }
    return merged.map { h in
        Change(
            range: NSRange(location: offsets[h.lo], length: offsets[h.hi] - offsets[h.lo]),
            text: b[h.newLo..<h.newHi].joined()
        )
    }
}

public func apply(_ changes: [Change], to text: String) -> String {
    let s = NSMutableString(string: text)
    for c in changes.sorted(by: { $0.range.location > $1.range.location }) {
        s.replaceCharacters(in: c.range, with: c.text)
    }
    return s as String
}

public func merge(base: String, current: String, proposed: String) -> [Change] {
    let mine = changes(from: base, to: current)
    return changes(from: base, to: proposed).compactMap { theirs in
        let lo = theirs.range.location, hi = NSMaxRange(theirs.range)
        var shift = 0
        for m in mine {
            let mlo = m.range.location, mhi = NSMaxRange(m.range)
            if mhi < lo || (mhi == lo && m.range.length > 0 && theirs.range.length > 0) {
                shift += m.delta
            } else if mlo > hi || (mlo == hi && m.range.length > 0 && theirs.range.length > 0) {
                break
            } else {
                return nil
            }
        }
        return Change(range: NSRange(location: lo + shift, length: theirs.range.length), text: theirs.text)
    }
}

public func shifted(_ changes: [Change]) -> [Change] {
    var shift = 0
    return changes.sorted { $0.range.location < $1.range.location }.map { c in
        defer { shift += c.delta }
        return Change(range: NSRange(location: c.range.location + shift, length: c.range.length), text: c.text)
    }
}

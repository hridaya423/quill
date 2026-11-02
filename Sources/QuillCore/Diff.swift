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

public func changes(from old: String, to new: String, coalesce: Bool = true) -> [Change] {
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
        if coalesce, var last = merged.last, bridgeable(a[last.hi..<h.lo]) {
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
    let mine = changes(from: base, to: current, coalesce: false)
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

public func replacing(_ edits: [(find: String, replace: String)], in text: String) -> String? {
    let doc = text as NSString
    var found: [Change] = []
    for edit in edits {
        if edit.find.isEmpty {
            guard !found.contains(where: { $0.range.location == doc.length }) else { return nil }
            let gap = text.isEmpty || text.hasSuffix("\n\n") ? "" : text.hasSuffix("\n") ? "\n" : "\n\n"
            found.append(Change(range: NSRange(location: doc.length, length: 0), text: gap + edit.replace))
            continue
        }
        let r = doc.range(of: edit.find)
        guard r.location != NSNotFound,
              doc.range(of: edit.find, range: NSRange(location: r.location + 1, length: doc.length - r.location - 1)).location == NSNotFound,
              !found.contains(where: { NSIntersectionRange($0.range, r).length > 0 })
        else { return nil }
        found.append(Change(range: r, text: edit.replace))
    }
    return apply(found, to: text)
}

public struct ItemScanner: Sendable {
    private var bytes: [UInt8] = []
    private var depth = 0
    private var quoted = false
    private var escaped = false
    private var closed = 0

    public init() {}

    public var raw: String { String(decoding: bytes, as: UTF8.self) }

    public mutating func feed(_ chunk: String) -> String? {
        let start = bytes.count
        bytes.append(contentsOf: chunk.utf8)
        var found: Int?
        for i in start..<bytes.count {
            let b = bytes[i]
            if quoted {
                if escaped { escaped = false } else if b == 0x5C { escaped = true } else if b == 0x22 { quoted = false }
                continue
            }
            switch b {
            case 0x22: quoted = true
            case 0x7B, 0x5B: depth += 1
            case 0x7D, 0x5D:
                depth -= 1
                if b == 0x7D, depth == 2 { found = i }
            default: break
            }
        }
        guard let found, found > closed else { return nil }
        closed = found
        return String(decoding: bytes[...found], as: UTF8.self) + "]}"
    }
}

func fillable(_ line: String) -> Bool {
    line.wholeMatch(of: /\s*(([-*+]|\d+[.)])\s*)?(\[ \]\s*)?([^:\n]{1,32}:\s*)?(\.\.\.|…|_+|TBD|TODO|\?+)?\s*/) != nil
}

public func stack(base: String, versions: [String]) -> String {
    struct Hunk { var lo: Int; var hi: Int; var lines: [String]; var who: Int }
    let old = base.components(separatedBy: "\n")
    var hunks: [Hunk] = []
    for (who, version) in versions.enumerated() {
        let new = version.components(separatedBy: "\n")
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in new.difference(from: old) {
            switch change {
            case .remove(let o, _, _): removed.insert(o)
            case .insert(let o, _, _): inserted.insert(o)
            }
        }
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, !removed.contains(i), !inserted.contains(j) {
                i += 1; j += 1
                continue
            }
            var h = Hunk(lo: i, hi: i, lines: [], who: who)
            while i < old.count, removed.contains(i) { i += 1 }
            while j < new.count, inserted.contains(j) { h.lines.append(new[j]); j += 1 }
            h.hi = i
            hunks.append(h)
        }
    }
    hunks.sort { ($0.lo, $0.hi, $0.who) < ($1.lo, $1.hi, $1.who) }
    var out: [String] = []
    var at = 0, k = 0
    while k < hunks.count {
        var group = [hunks[k]]
        var lo = hunks[k].lo, hi = hunks[k].hi
        k += 1
        while k < hunks.count, hunks[k].lo < hi || hunks[k].lo == lo {
            hi = max(hi, hunks[k].hi)
            lo = min(lo, hunks[k].lo)
            group.append(hunks[k])
            k += 1
        }
        out += old[at..<lo]
        at = hi
        let authors = Array(Set(group.map(\.who))).sorted()
        func region(_ who: Int) -> [String] {
            var lines: [String] = [], p = lo
            for h in group where h.who == who {
                lines += old[p..<h.lo]
                lines += h.lines
                p = h.hi
            }
            return lines + old[p..<hi]
        }
        if authors.count == 1 {
            out += region(authors[0])
        } else if old[lo..<hi].allSatisfy(fillable) {
            out += interleave(Array(old[lo..<hi]), authors.map(region))
        } else {
            out += region(authors[0])
        }
    }
    out += old[at...]
    return out.joined(separator: "\n")
}

func indent(_ s: String) -> Int { s.prefix { $0 == " " || $0 == "\t" }.count }

func bulleted(_ s: String) -> Bool {
    s.trimmingCharacters(in: .whitespaces).first.map { "-*+".contains($0) || $0.isNumber } ?? false
}

func interleave(_ base: [String], _ regions: [[String]]) -> [String] {
    let top = base.filter(bulleted).map(indent).min()
    let isStart = { (line: String) in top != nil && bulleted(line) && indent(line) == top }
    let starts = base.indices.filter { isStart(base[$0]) }
    let slots = Array(base[0..<(starts.first ?? base.count)])
    let blocks = starts.indices.map { k in Array(base[starts[k]..<(k + 1 < starts.count ? starts[k + 1] : base.count)]) }
    var out: [String] = []
    var heads = Array(repeating: [String](), count: slots.count)
    var stray: [String] = []
    var theirs: [[[String]]] = []
    for region in regions {
        var j = 0, mine: [[String]] = []
        for line in region {
            if isStart(line) {
                mine.append([line])
            } else if !mine.isEmpty {
                mine[mine.count - 1].append(line)
            } else if let k = (j..<slots.count).first(where: { line.hasPrefix(slots[$0].replacing(/\s+$/, with: "")) }) {
                j = k
                if line != slots[k], !heads[k].contains(line) { heads[k].append(line) }
            } else if slots.isEmpty {
                if !stray.contains(line) { stray.append(line) }
            } else if line != slots[j], !heads[j].contains(line) {
                heads[j].append(line)
            }
        }
        theirs.append(mine)
    }
    for (k, slot) in slots.enumerated() { out += heads[k].isEmpty ? [slot] : heads[k] }
    out += stray
    var placed: [[String]] = []
    for k in 0..<(theirs.map(\.count).max() ?? 0) {
        var any = false
        for mine in theirs where k < mine.count && (k >= blocks.count || mine[k] != blocks[k]) {
            any = true
            guard !placed.contains(mine[k]) else { continue }
            placed.append(mine[k])
            out += mine[k]
        }
        if !any, k < blocks.count { out += blocks[k] }
    }
    return out
}

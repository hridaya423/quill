import Foundation

public struct Hunk: Equatable, Sendable, Identifiable {
    public var id: Int
    public var turn: Int
    public var range: NSRange
    public var old: String
    public var new: String
    public var flags: [String]
    public var touched: Bool
    public var by: String?
}

public struct Review: Equatable, Sendable {
    public private(set) var hunks: [Hunk] = []
    private var serial = 0

    public init() {}

    public var isEmpty: Bool { hunks.isEmpty }

    public func hunk(_ id: Int) -> Hunk? {
        hunks.first { $0.id == id }
    }

    public func hunk(at location: Int) -> Hunk? {
        hunks.first { location >= $0.range.location && location <= NSMaxRange($0.range) }
    }

    public func turn(_ turn: Int) -> [Hunk] {
        hunks.filter { $0.turn == turn }
    }

    public mutating func agent(_ r: NSRange, before: NSString, after: NSString, turn: Int, flags: [String] = [], by: String? = nil) {
        let delta = after.length - before.length
        let lo0 = r.location, hi0 = NSMaxRange(r)
        var touching: [Hunk] = [], rest: [Hunk] = []
        for h in hunks {
            if h.range.location <= hi0 && NSMaxRange(h.range) >= lo0 { touching.append(h) } else { rest.append(h) }
        }
        touching.sort { $0.range.location < $1.range.location }
        let lo = min(lo0, touching.first?.range.location ?? lo0)
        let hi = max(hi0, touching.map { NSMaxRange($0.range) }.max() ?? hi0)
        var old = "", at = lo
        for h in touching {
            if h.range.location > at { old += before.substring(with: NSRange(location: at, length: h.range.location - at)) }
            old += h.old
            at = max(at, NSMaxRange(h.range))
        }
        if hi > at { old += before.substring(with: NSRange(location: at, length: hi - at)) }
        let range = NSRange(location: lo, length: hi - lo + delta)
        let new = after.substring(with: range)
        hunks = rest.map { h in
            var h = h
            if h.range.location > hi0 { h.range.location += delta }
            return h
        }
        if old != new {
            serial += 1
            let marks = Array(Set(touching.flatMap(\.flags) + flags)).sorted()
            hunks.append(Hunk(id: serial, turn: turn, range: range, old: old, new: new, flags: marks, touched: false, by: by ?? touching.first?.by))
        }
        hunks.sort { $0.range.location < $1.range.location }
    }

    @discardableResult
    public mutating func user(_ r: NSRange, length n: Int) -> [Hunk] {
        let delta = n - r.length
        let lo0 = r.location, hi0 = NSMaxRange(r)
        var crossed: [Hunk] = []
        hunks = hunks.compactMap { h in
            var h = h
            let hlo = h.range.location, hhi = NSMaxRange(h.range)
            if hi0 <= hlo {
                h.range.location += delta
                return h
            }
            if lo0 >= hhi { return h }
            if lo0 >= hlo, hi0 <= hhi {
                h.range.length += delta
                h.touched = true
                return h
            }
            crossed.append(h)
            return nil
        }
        return crossed
    }

    public mutating func remove(_ id: Int) -> Hunk? {
        guard let i = hunks.firstIndex(where: { $0.id == id }) else { return nil }
        return hunks.remove(at: i)
    }

    public mutating func removeAll() -> [Hunk] {
        defer { hunks = [] }
        return hunks
    }

    public func accepted(_ text: String) -> String {
        guard !hunks.isEmpty else { return text }
        let s = NSMutableString(string: text)
        for h in hunks.sorted(by: { $0.range.location > $1.range.location }) where NSMaxRange(h.range) <= s.length {
            s.replaceCharacters(in: h.range, with: h.old)
        }
        return s as String
    }
}

public func paragraph(around r: NSRange, in doc: NSString) -> NSRange {
    let start = r.location == 0 ? NSNotFound : doc.range(of: "\n\n", options: .backwards, range: NSRange(location: 0, length: r.location)).location
    let lo = start == NSNotFound ? 0 : start + 2
    let tail = NSMaxRange(r)
    let end = doc.range(of: "\n\n", range: NSRange(location: tail, length: doc.length - tail)).location
    let hi = end == NSNotFound ? doc.length : end
    return NSRange(location: lo, length: max(0, hi - lo))
}

public func exchange(_ h: Hunk, request: String, outcome: Outcome, in doc: NSString, at r: NSRange) -> Exchange {
    let p = paragraph(around: r, in: doc)
    let prefix = doc.substring(with: NSRange(location: p.location, length: r.location - p.location))
    let suffix = doc.substring(with: NSRange(location: NSMaxRange(r), length: NSMaxRange(p) - NSMaxRange(r)))
    return Exchange(request: request, before: prefix + h.old + suffix, proposed: prefix + h.new + suffix,
                    final: prefix + doc.substring(with: r) + suffix, outcome: outcome)
}

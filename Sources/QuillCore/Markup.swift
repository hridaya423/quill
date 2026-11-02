import Foundation

public enum Style: Equatable, Sendable {
    case heading(Int)
    case bold
    case italic
    case code
    case codeBlock
    case link
    case quote
    case list
    case strike
    case rule
    case highlight
    case done
}

public struct Ornament: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case bullet
        case box(Bool)
        case blank
        case rule
    }
    public var range: NSRange
    public var kind: Kind
}

public struct Target: Equatable, Sendable {
    public var range: NSRange
    public var to: String
    public var note: Bool
}

public struct Span: Equatable, Sendable {
    public var range: NSRange
    public var style: Style
}

public struct Markup: Equatable, Sendable {
    public var spans: [Span] = []
    public var markers: [NSRange] = []
    public var ornaments: [Ornament] = []
    public var targets: [Target] = []
}

private func rx(_ p: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
}

private let heading = rx(#"^(#{1,6}[ \t]+)"#)
private let quote = rx(#"^(>[ \t]?)"#)
private let list = rx(#"^[ \t]*([-*+]|\d+[.)])[ \t]+(?:(\[[ xX]\])[ \t]+)?"#)
private let wiki = rx(#"(\[\[)([^\]\n]+)(\]\])"#)
private let rule = rx(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)
private let fence = rx(#"^[ \t]*```"#)
private let inline: [(NSRegularExpression, Style)] = [
    (rx(#"(`)([^`\n]+)(`)"#), .code),
    (rx(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#), .bold),
    (rx(#"(?<![*\w])(\*|_)(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*\w])"#), .italic),
    (rx(#"(~~)(?=\S)(.+?)(?<=\S)~~"#), .strike),
    (rx(#"(==)(?=\S)(.+?)(?<=\S)=="#), .highlight),
]
private let link = rx(#"(\[)([^\]\n]+)(\]\([^)\s]+\))"#)

public func isFenceLine(_ text: NSString, _ line: NSRange) -> Bool {
    fence.firstMatch(in: text as String, range: line) != nil
}

public func markup(_ text: NSString, line: NSRange, inFence: Bool) -> Markup {
    var m = Markup()
    let s = text as String
    if isFenceLine(text, line) || inFence {
        m.spans.append(Span(range: line, style: .codeBlock))
        if isFenceLine(text, line) { m.markers.append(line) }
        return m
    }
    if line.length == 0 { return m }
    if rule.firstMatch(in: s, range: line) != nil {
        m.spans.append(Span(range: line, style: .rule))
        m.ornaments.append(Ornament(range: line, kind: .rule))
        return m
    }
    var body = line
    if let h = heading.firstMatch(in: s, range: line) {
        let marker = h.range(at: 1)
        let level = text.substring(with: marker).filter { $0 == "#" }.count
        m.spans.append(Span(range: line, style: .heading(level)))
        m.markers.append(marker)
        body = NSRange(location: NSMaxRange(marker), length: NSMaxRange(line) - NSMaxRange(marker))
    } else if let q = quote.firstMatch(in: s, range: line) {
        m.spans.append(Span(range: line, style: .quote))
        m.markers.append(q.range(at: 1))
        body = NSRange(location: NSMaxRange(q.range), length: NSMaxRange(line) - NSMaxRange(q.range))
    } else if let l = list.firstMatch(in: s, range: line) {
        let bullet = l.range(at: 1), box = l.range(at: 2)
        m.spans.append(Span(range: bullet, style: .list))
        body = NSRange(location: NSMaxRange(l.range), length: NSMaxRange(line) - NSMaxRange(l.range))
        let unordered = "-*+".contains(text.substring(with: bullet))
        if box.location != NSNotFound {
            let checked = text.substring(with: box).lowercased() == "[x]"
            if unordered { m.ornaments.append(Ornament(range: bullet, kind: .blank)) }
            m.ornaments.append(Ornament(range: box, kind: .box(checked)))
            if checked, body.length > 0 { m.spans.append(Span(range: body, style: .done)) }
        } else if unordered {
            m.ornaments.append(Ornament(range: bullet, kind: .bullet))
        }
    }

    var taken: [NSRange] = []
    func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }

    for match in wiki.matches(in: s, range: body) where free(match.range) {
        let inner = match.range(at: 2)
        let content = text.substring(with: inner)
        let bar = (content as NSString).range(of: "|")
        let note = bar.location == NSNotFound ? content : String(content.prefix(bar.location))
        let shown = bar.location == NSNotFound ? inner : NSRange(location: inner.location + bar.location + 1, length: inner.length - bar.location - 1)
        guard shown.length > 0 else { continue }
        m.spans.append(Span(range: shown, style: .link))
        m.markers += [NSRange(location: match.range.location, length: shown.location - match.range.location), match.range(at: 3)]
        m.targets.append(Target(range: shown, to: note.trimmingCharacters(in: .whitespaces), note: true))
        taken.append(match.range)
    }
    for match in link.matches(in: s, range: body) where free(match.range) {
        let tail = text.substring(with: match.range(at: 3))
        m.spans.append(Span(range: match.range(at: 2), style: .link))
        m.markers += [match.range(at: 1), match.range(at: 3)]
        m.targets.append(Target(range: match.range(at: 2), to: String(tail.dropFirst(2).dropLast()), note: false))
        taken.append(match.range)
    }
    for (pattern, style) in inline {
        for match in pattern.matches(in: s, range: body) {
            let open = match.range(at: 1), content = match.range(at: 2)
            let close = NSRange(location: NSMaxRange(content), length: open.length)
            if style == .code {
                guard free(match.range) else { continue }
                taken.append(match.range)
            } else if !free(open) || !free(close) {
                continue
            }
            m.spans.append(Span(range: content, style: style))
            m.markers += [open, close]
        }
    }
    return m
}

public func fenceState(before location: Int, in text: NSString) -> Bool {
    var inFence = false
    var search = NSRange(location: 0, length: location)
    while true {
        let hit = text.range(of: "```", options: .literal, range: search)
        if hit.location == NSNotFound { return inFence }
        let line = text.lineRange(for: hit)
        if isFenceLine(text, line), NSMaxRange(line) <= location { inFence.toggle() }
        let next = max(NSMaxRange(line), NSMaxRange(hit))
        search = NSRange(location: next, length: max(0, location - next))
    }
}

public func wordCount(_ text: String) -> Int {
    var count = 0
    var inToken = false
    var counted = false
    for scalar in text.unicodeScalars {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            inToken = false
            counted = false
            continue
        }
        inToken = true
        if !counted, CharacterSet.alphanumerics.contains(scalar) {
            count += 1
            counted = true
        }
    }
    return count
}

public struct Heading: Equatable, Sendable, Identifiable {
    public var level: Int
    public var title: String
    public var location: Int
    public var id: Int { location }
}

public func outline(_ text: NSString) -> [Heading] {
    var found: [Heading] = []
    var inFence = false
    var cursor = 0
    while cursor < text.length {
        let line = text.lineRange(for: NSRange(location: cursor, length: 0))
        if isFenceLine(text, line) {
            inFence.toggle()
        } else if !inFence, let h = heading.firstMatch(in: text as String, range: line) {
            let marker = h.range(at: 1)
            let title = text.substring(with: NSRange(location: NSMaxRange(marker), length: NSMaxRange(line) - NSMaxRange(marker)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                found.append(Heading(level: text.substring(with: marker).filter { $0 == "#" }.count, title: title, location: line.location))
            }
        }
        cursor = NSMaxRange(line)
    }
    return found
}

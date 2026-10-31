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
}

public struct Span: Equatable, Sendable {
    public var range: NSRange
    public var style: Style
}

public struct Markup: Equatable, Sendable {
    public var spans: [Span] = []
    public var markers: [NSRange] = []
}

private func rx(_ p: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
}

private let heading = rx(#"^(#{1,6}[ \t]+)"#)
private let quote = rx(#"^(>[ \t]?)"#)
private let list = rx(#"^[ \t]*([-*+]|\d+[.)])[ \t]+"#)
private let rule = rx(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)
private let fence = rx(#"^[ \t]*```"#)
private let inline: [(NSRegularExpression, Style)] = [
    (rx(#"(`)([^`\n]+)(`)"#), .code),
    (rx(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#), .bold),
    (rx(#"(?<![*\w])(\*|_)(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*\w])"#), .italic),
    (rx(#"(~~)(?=\S)(.+?)(?<=\S)~~"#), .strike),
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
        m.markers.append(line)
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
        m.spans.append(Span(range: l.range(at: 1), style: .list))
        body = NSRange(location: NSMaxRange(l.range), length: NSMaxRange(line) - NSMaxRange(l.range))
    }

    var taken: [NSRange] = []
    func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }

    for match in link.matches(in: s, range: body) where free(match.range) {
        m.spans.append(Span(range: match.range(at: 2), style: .link))
        m.markers += [match.range(at: 1), match.range(at: 3)]
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

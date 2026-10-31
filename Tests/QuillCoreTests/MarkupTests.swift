import Foundation
import Testing
@testable import QuillCore

func scan(_ s: String, inFence: Bool = false) -> (Markup, NSString) {
    let t = s as NSString
    return (markup(t, line: NSRange(location: 0, length: t.length), inFence: inFence), t)
}

func texts(_ ranges: [NSRange], _ t: NSString) -> [String] { ranges.map { t.substring(with: $0) } }

@Test func headingHidesHashes() {
    let (m, t) = scan("## Pitch")
    #expect(m.spans.first?.style == .heading(2))
    #expect(texts(m.markers, t) == ["## "])
}

@Test func boldItalicCodeAndLink() {
    let (m, t) = scan("Say **bold**, *soft*, `x*y*z` and [Quill](https://q.app).")
    let styled = m.spans.map { ($0.style, t.substring(with: $0.range)) }
    #expect(styled.contains { $0 == (.bold, "bold") })
    #expect(styled.contains { $0 == (.italic, "soft") })
    #expect(styled.contains { $0 == (.code, "x*y*z") })
    #expect(styled.contains { $0 == (.link, "Quill") })
    #expect(!styled.contains { $0.0 == .italic && $0.1 == "y" })
    #expect(texts(m.markers, t).contains("](https://q.app)"))
}

@Test func snakeCaseIsNotItalic() {
    let (m, _) = scan("call some_long_name here")
    #expect(m.spans.isEmpty)
}

@Test func listQuoteRule() {
    #expect(scan("- item").0.spans.first?.style == .list)
    #expect(scan("12. item").0.spans.first?.style == .list)
    #expect(scan("> said").0.spans.first?.style == .quote)
    #expect(scan("---").0.spans.first?.style == .rule)
}

@Test func fenceTracking() {
    let t = "a\n```\ncode **not bold**\n```\nb" as NSString
    #expect(fenceState(before: 0, in: t) == false)
    let codeLine = t.range(of: "code")
    #expect(fenceState(before: codeLine.location, in: t) == true)
    #expect(fenceState(before: t.range(of: "b", options: .backwards).location, in: t) == false)
    #expect(scan("code **not bold**", inFence: true).0.spans.map(\.style) == [.codeBlock])
}

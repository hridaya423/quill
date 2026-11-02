import Foundation
import Testing
@testable import Quill

@Test func googleDocLinksReadThroughTheirTextExport() {
    let doc = URL(string: "https://docs.google.com/document/d/1AbC_xyz/edit?usp=sharing")!
    #expect(Links.source(for: doc).absoluteString == "https://docs.google.com/document/d/1AbC_xyz/export?format=txt")
    let sheet = URL(string: "https://docs.google.com/spreadsheets/d/9Zz/edit#gid=0")!
    #expect(Links.source(for: sheet).absoluteString == "https://docs.google.com/spreadsheets/d/9Zz/export?format=csv")
    let page = URL(string: "https://lu.ma/hack")!
    #expect(Links.source(for: page) == page)
}

@Test func pagesReduceToTheirWords() {
    let html = """
    <html><head><title>Build Night &amp; Demo</title><meta name="description" content="A 24-hour hackathon in SF."><style>p{}</style></head>
    <body><script>var x = 1</script><h1>Rules</h1><p>Teams of up to&nbsp;4.</p><ul><li>Prize: $5k</li></ul></body></html>
    """
    let text = Links.readable(html: html)
    #expect(text.contains("Build Night & Demo"))
    #expect(text.contains("A 24-hour hackathon in SF."))
    #expect(text.contains("Teams of up to 4."))
    #expect(text.contains("Prize: $5k"))
    #expect(!text.contains("var x"))
    #expect(!text.contains("p{}"))
}

@Test func linksAreFoundOncePerNote() {
    let found = Links.found(in: ["see https://lu.ma/hack", "brief: https://lu.ma/hack and https://docs.google.com/document/d/1/edit"])
    #expect(found.map(\.absoluteString) == ["https://lu.ma/hack", "https://docs.google.com/document/d/1/edit"])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["QUILL_NET"] != nil)) func readsALiveEventPage() async throws {
    let page = try #require(await Links.fetch(URL(string: ProcessInfo.processInfo.environment["QUILL_NET"]!)!))
    print("<<<\(page.text.prefix(1500))>>>")
    #expect(page.text.count > 200)
}

import Foundation

enum Links {
    struct Page: Sendable {
        var url: URL
        var text: String
    }

    static let limit = 14_000
    @MainActor private static var cache: [URL: Page] = [:]

    static func found(in texts: [String]) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        var seen: [URL] = []
        for text in texts {
            for match in detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? [] {
                guard let url = match.url, ["http", "https"].contains(url.scheme ?? ""), !seen.contains(url) else { continue }
                seen.append(url)
            }
        }
        return Array(seen.prefix(4))
    }

    static func source(for url: URL) -> URL {
        guard url.host?.hasSuffix("docs.google.com") == true else { return url }
        let parts = url.pathComponents
        guard let d = parts.firstIndex(of: "d"), d + 1 < parts.count, d > 0 else { return url }
        let kind = parts[d - 1]
        let format = kind == "spreadsheets" ? "csv" : "txt"
        guard ["document", "spreadsheets", "presentation"].contains(kind) else { return url }
        return URL(string: "https://docs.google.com/\(kind)/d/\(parts[d + 1])/export?format=\(format)") ?? url
    }

    @MainActor
    static func read(_ urls: [URL]) async -> [Page] {
        await withTaskGroup(of: Page?.self) { group in
            for url in urls {
                if let hit = cache[url] { group.addTask { hit }; continue }
                group.addTask { await fetch(url) }
            }
            var pages: [Page] = []
            for await page in group { if let page { pages.append(page) } }
            for page in pages { cache[page.url] = page }
            return urls.compactMap { url in pages.first { $0.url == url } }
        }
    }

    nonisolated static func fetch(_ url: URL) async -> Page? {
        var request = URLRequest(url: source(for: url), timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        let html = (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("html")
        let text = html ? readable(html: body) : body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 40, !text.contains("Sign in - Google Accounts") else { return nil }
        return Page(url: url, text: String(text.prefix(limit)))
    }

    nonisolated static func readable(html: String) -> String {
        var parts: [String] = []
        if let title = html.firstMatch(of: /(?is)<title[^>]*>(.*?)<\/title>/) { parts.append(decode(String(title.1))) }
        for meta in html.matches(of: /(?i)<meta[^>]+(?:name|property)="(?:description|og:description)"[^>]+content="([^"]*)"/) {
            let line = decode(String(meta.1))
            if !parts.contains(line) { parts.append(line) }
        }
        for block in html.matches(of: /(?is)<script[^>]+application\/ld\+json[^>]*>(.*?)<\/script>/) {
            parts.append(String(block.1).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var body = html.replacing(/(?is)<(script|style|noscript|svg|head)\b.*?<\/\1>/, with: " ")
        body = body.replacing(/(?i)<\s*(br|\/p|\/div|\/li|\/h[1-6]|\/tr)\s*\/?>/, with: "\n")
        body = body.replacing(/<[^>]+>/, with: " ")
        body = decode(body)
        let lines = body.components(separatedBy: "\n")
            .map { $0.replacing(/[ \t\u{00A0}]+/, with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        parts.append(lines.joined(separator: "\n"))
        return parts.joined(separator: "\n\n")
    }

    nonisolated static func decode(_ s: String) -> String {
        var out = s
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&nbsp;", " "), ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&mdash;", "—"), ("&ndash;", "–")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }
}

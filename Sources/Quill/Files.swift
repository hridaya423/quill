import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

final class Files: NSObject, WKURLSchemeHandler {
    static let scheme = "quill-file"

    static func url(_ file: URL) -> String {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = ""
        parts.path = file.standardizedFileURL.path
        return parts.url?.absoluteString ?? ""
    }

    nonisolated(unsafe) static var roots: Set<String> = []

    static func allowed(_ raw: String) -> Bool {
        let resolve = { (p: String) in URL(fileURLWithPath: p).resolvingSymlinksInPath().path }
        let path = resolve(raw)
        let home = resolve(NSHomeDirectory())
        if path.hasPrefix(home + "/Library/") { return false }
        let bases = roots.map(resolve).filter { $0 != home && path.hasPrefix($0 + "/") }
        guard let base = bases.max(by: { $0.count < $1.count }) ?? (path.hasPrefix(home + "/") ? home : nil) else { return false }
        return !path.dropFirst(base.count + 1).split(separator: "/").contains { $0.hasPrefix(".") }
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url,
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path,
              Self.allowed(path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        var body = data
        var status = 200
        var headers = ["Content-Type": mime, "Accept-Ranges": "bytes", "Cache-Control": "no-cache"]
        if let range = task.request.value(forHTTPHeaderField: "Range"),
           let match = range.firstMatch(of: /bytes=(\d+)-(\d*)/),
           let start = Int(match.1), start < data.count {
            let end = min(Int(match.2) ?? start + (8 << 20) - 1, data.count - 1)
            body = data.subdata(in: start..<(end + 1))
            status = 206
            headers["Content-Range"] = "bytes \(start)-\(end)/\(data.count)"
        }
        headers["Content-Length"] = String(body.count)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

@MainActor
enum Embeds {
    static let images: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "avif", "heic", "tif", "tiff"]
    static let video: Set<String> = ["mp4", "mov", "webm", "m4v"]
    static let audio: Set<String> = ["mp3", "m4a", "wav", "ogg", "flac", "aac"]

    static func targets(in text: String) -> [String] {
        var found: [String] = []
        for m in text.matches(of: /!\[\[([^\]\n]+)\]\]/) {
            let inner = String(m.1)
            let target = inner.split(separator: "|", maxSplits: 1).first.map { String($0).replacingOccurrences(of: "\\", with: "") } ?? inner
            found.append(target.trimmingCharacters(in: .whitespaces))
        }
        for m in text.matches(of: /!\[[^\]\n]*\]\(([^)\s]+)\)/) {
            let src = String(m.1)
            if !src.lowercased().hasPrefix("http") { found.append("path:" + (src.removingPercentEncoding ?? src)) }
        }
        return Array(Set(found))
    }

    static func payload(_ target: String, from note: URL?, root: URL, notes: [Note], nested: Bool = false) -> [String: Any] {
        if target.hasPrefix("path:") {
            let raw = String(target.dropFirst(5))
            let base = note?.deletingLastPathComponent() ?? root
            let file = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : base.appending(path: raw)
            return describe(file.standardizedFileURL, name: raw)
        }
        let parts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        let sub = parts.count > 1 ? parts[1] : nil
        let ext = (name as NSString).pathExtension.lowercased()
        if !ext.isEmpty, ext != "md" {
            guard let file = locate(name, from: note, root: root) else { return ["kind": "missing", "title": name] }
            return describe(file, name: name)
        }
        let url: URL?
        if name.isEmpty {
            url = note
        } else {
            let bare = ext == "md" ? String(name.dropLast(3)) : name
            url = notes.first { $0.title.caseInsensitiveCompare(bare) == .orderedSame && !bare.contains("/") }?.url
                ?? notes.first { $0.url.path.lowercased().hasSuffix("/" + bare.lowercased() + ".md") }?.url
                ?? locate(bare + ".md", from: note, root: root)
        }
        guard let url, Files.allowed(url.path) else { return ["kind": "missing", "title": name] }
        if nested { return ["kind": "note", "title": url.deletingPathExtension().lastPathComponent] }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return ["kind": "missing", "title": name] }
        let title = url.deletingPathExtension().lastPathComponent
        let shown = excerpt(body(text), sub)
        var inner: [String: Any] = [:]
        for t in targets(in: shown) {
            let p = payload(t, from: url, root: root, notes: notes, nested: true)
            if p["kind"] as? String != "note" { inner[t] = p } else { inner[t] = ["kind": "link", "title": p["title"] ?? t] }
        }
        return ["kind": "note", "title": title, "path": url.path, "text": shown, "embeds": inner]
    }

    static func dimensions(_ file: URL) -> (Int, Int)? {
        if file.pathExtension.lowercased() == "svg" {
            guard let size = NSImage(contentsOf: file)?.size, size.width > 0, size.height > 0 else { return nil }
            return (Int(size.width.rounded()), Int(size.height.rounded()))
        }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        return (props[kCGImagePropertyOrientation] as? Int ?? 1) >= 5 ? (height, width) : (width, height)
    }

    static func describe(_ file: URL, name: String) -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path), Files.allowed(file.path) else { return ["kind": "missing", "title": name] }
        let ext = file.pathExtension.lowercased()
        let url = Files.url(file)
        if images.contains(ext) {
            var out: [String: Any] = ["kind": "image", "url": url]
            if let (width, height) = dimensions(file) {
                out["width"] = width
                out["height"] = height
            }
            return out
        }
        if video.contains(ext) { return ["kind": "media", "url": url, "media": "video"] }
        if audio.contains(ext) { return ["kind": "media", "url": url, "media": "audio"] }
        return ["kind": "file", "url": file.absoluteString, "name": file.lastPathComponent]
    }

    private static var indexes: [String: [String: [URL]]] = [:]
    private static var walks: [String: Int] = [:]
    private static var generation = 0

    static func forget(_ root: URL) {
        let key = root.standardizedFileURL.path
        indexes[key] = nil
        walks[key] = nil
    }

    static func noticed(_ paths: [String], root: URL) {
        guard let index = indexes[root.standardizedFileURL.path] else { return }
        let plain = { (path: String) in path.hasPrefix("/private/") ? String(path.dropFirst(8)) : path }
        let key = plain(root.path)
        for path in paths {
            let file = plain(URL(fileURLWithPath: path).standardizedFileURL.path)
            guard file.hasPrefix(key + "/"), !file.dropFirst(key.count).split(separator: "/").contains(where: { $0.hasPrefix(".") || Workspace.skipped.contains(String($0)) }) else { continue }
            let known = index[(file as NSString).lastPathComponent.lowercased()]?.contains { plain($0.path) == file } ?? false
            if known != FileManager.default.fileExists(atPath: path) { return forget(root) }
        }
    }

    static func warm(_ root: URL) {
        let key = root.standardizedFileURL.path
        guard indexes[key] == nil, walks[key] == nil else { return }
        generation += 1
        let mine = generation
        walks[key] = mine
        Task.detached(priority: .utility) {
            let found = walk(root)
            await MainActor.run {
                guard walks[key] == mine else { return }
                walks[key] = nil
                indexes[key] = found
            }
        }
    }

    private nonisolated static func walk(_ root: URL) -> [String: [URL]] {
        var found: [String: [URL]] = [:]
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = walker?.nextObject() as? URL {
            if Workspace.skipped.contains(url.lastPathComponent) { walker?.skipDescendants(); continue }
            found[url.lastPathComponent.lowercased(), default: []].append(url)
        }
        return found
    }

    private static func index(_ root: URL) -> [String: [URL]] {
        let key = root.standardizedFileURL.path
        if let known = indexes[key] { return known }
        let found = walk(root)
        walks[key] = nil
        indexes[key] = found
        return found
    }

    static func locate(_ name: String, from note: URL?, root: URL) -> URL? {
        let fm = FileManager.default
        for base in [note?.deletingLastPathComponent(), root].compactMap({ $0 }) {
            let direct = base.appending(path: name)
            if fm.fileExists(atPath: direct.path) { return direct.standardizedFileURL }
        }
        let suffix = "/" + name.lowercased()
        return index(root)[(name as NSString).lastPathComponent.lowercased()]?
            .filter { $0.path.lowercased().hasSuffix(suffix) }
            .min { $0.pathComponents.count < $1.pathComponents.count }
    }

    static func body(_ text: String) -> String {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return text }
        let lines = text.components(separatedBy: "\n")
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return text }
        return lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    static func excerpt(_ text: String, _ sub: String?) -> String {
        guard let sub, !sub.isEmpty else { return text }
        let lines = text.components(separatedBy: "\n")
        if sub.hasPrefix("^") {
            let id = sub.dropFirst()
            guard let at = lines.firstIndex(where: { $0.hasSuffix(" ^\(id)") || $0 == "^\(id)" }) else { return text }
            var start = at
            while start > 0, !lines[start - 1].trimmingCharacters(in: .whitespaces).isEmpty { start -= 1 }
            return lines[start...at].joined(separator: "\n").replacingOccurrences(of: " ^\(id)", with: "")
        }
        let wanted = sub.split(separator: "#").last.map(String.init)?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        guard let at = lines.firstIndex(where: { line in
            guard let m = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) else { return false }
            return m.2.trimmingCharacters(in: .whitespaces).lowercased() == wanted
        }) else { return text }
        let level = lines[at].prefix { $0 == "#" }.count
        var end = at + 1
        while end < lines.count {
            if let m = lines[end].firstMatch(of: /^(#{1,6})\s/), m.1.count <= level { break }
            end += 1
        }
        return lines[at..<end].joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}

import Foundation
import QuillCore

func browsable(_ path: String) -> Bool {
    let base = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.resolvingSymlinksInPath().path
    let target = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    guard target.hasPrefix(base + "/") else { return false }
    let parts = target.dropFirst(base.count + 1).split(separator: "/")
    return parts.first != "Library" && !parts.contains { $0.hasPrefix(".") }
}

func located(_ path: String) -> URL {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
    if path == "~" { return home }
    return home.appending(path: path.hasPrefix("~/") ? String(path.dropFirst(2)) : path)
}

struct Tool {
    var name: String
    var description: String
    var parameters: [String: Any]

    static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "additionalProperties": false, "required": Array(properties.keys).sorted(), "properties": properties]
    }

    @MainActor static let all: [Tool] = [
        Tool(name: "edit_document",
             description: "Replace exact passages of the open document. Each find is copied exactly from the document and is long enough to be unique. Edits must not overlap. An empty find adds the replace text at the end of the document.",
             parameters: object(["edits": ["type": "array", "items": object(["find": ["type": "string"], "replace": ["type": "string"]])]])),
        Tool(name: "leave_notes",
             description: "Leave margin notes on the document without changing it. Each quote is copied exactly from the document, 3 to 12 words.",
             parameters: object(["notes": ["type": "array", "items": object([
                 "quote": ["type": "string"], "lens": ["type": "string", "enum": lenses], "note": ["type": "string"],
             ])]])),
        Tool(name: "list_folder",
             description: "List a folder on the writer's Mac. The path is absolute or relative to their home folder.",
             parameters: object(["path": ["type": "string"]])),
        Tool(name: "read_file",
             description: "Read a text file on the writer's Mac. The path is absolute or relative to their home folder.",
             parameters: object(["path": ["type": "string"]])),
    ]

    static let system = """
    You work inside a text editor. When the writer names a folder or file, call list_folder or read_file first, and read what explains it before you write. \
    Never write about something you haven't read. \
    To change the document, write your short reply, then call edit_document once with every edit. To leave margin notes, call leave_notes once.
    """
}

struct ToolResult {
    var result: String
    var again: Bool
}

@MainActor
final class Toolbox {
    private(set) var doc: String
    private let readable: [URL]
    private let events: @MainActor (AgentEvent) -> Void
    private var open: [Int: (name: String, scanner: ItemScanner, shown: Int)] = [:]

    init(doc: String, readable: [URL], events: @escaping @MainActor (AgentEvent) -> Void) {
        self.doc = doc
        self.readable = readable
        self.events = events
    }

    func start(_ index: Int, _ name: String) {
        open[index] = (name, ItemScanner(), 0)
        switch name {
        case "leave_notes": events(.activity("Reading closely"))
        case "edit_document": events(.activity("Editing"))
        default: break
        }
    }

    func feed(_ index: Int, _ chunk: String) {
        guard var tool = open[index] else { return }
        let prefix = tool.scanner.feed(chunk)
        if tool.name == "edit_document", let prefix, let edits = Self.edits(prefix), edits.count > tool.shown, let next = replacing(edits, in: doc) {
            if let last = edits.last, !last.find.isEmpty { events(.focus(last.find)) }
            tool.shown = edits.count
            events(.proposed(next))
        }
        open[index] = tool
    }

    func finish(_ index: Int) -> (name: String, input: String, result: ToolResult)? {
        guard let tool = open.removeValue(forKey: index) else { return nil }
        let raw = tool.scanner.raw
        return (tool.name, raw, run(tool.name, raw, shown: tool.shown))
    }

    private func run(_ name: String, _ raw: String, shown: Int) -> ToolResult {
        let input = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
        switch name {
        case "edit_document":
            guard let edits = Self.edits(raw) else { return ToolResult(result: "The edits were malformed. Send them again.", again: true) }
            guard let next = replacing(edits, in: doc) else {
                return ToolResult(result: "An edit didn't match. Each find must appear exactly once in the document, copied exactly. Try again.", again: true)
            }
            doc = next
            if edits.count > shown { events(.proposed(next)) }
            return ToolResult(result: "Done.", again: false)
        case "leave_notes":
            guard let notes = input["notes"], let data = try? JSONSerialization.data(withJSONObject: notes) else {
                return ToolResult(result: "The notes were malformed. Send them again.", again: true)
            }
            events(.notes(String(decoding: data, as: UTF8.self)))
            return ToolResult(result: "Noted.", again: false)
        case "read_file", "list_folder":
            let asked = input["path"] as? String ?? ""
            let url = located(asked)
            events(.activity(activity(name == "read_file" ? "read" : "search", file: url.path, title: nil)))
            guard permits(kind: "read", paths: [url.path], file: nil, readable: readable) else {
                return ToolResult(result: "Quill can't open \(asked). Hidden folders and Library are off limits.", again: true)
            }
            return ToolResult(result: name == "read_file" ? Self.read(url) : Self.list(url), again: true)
        default:
            return ToolResult(result: "There is no tool called \(name).", again: true)
        }
    }

    static func read(_ url: URL) -> String {
        var folder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) else { return "Nothing exists at \(url.path)." }
        if folder.boolValue { return list(url) }
        guard let data = try? Data(contentsOf: url), !data.prefix(4096).contains(0), let text = String(data: data, encoding: .utf8) else {
            return "\(url.lastPathComponent) isn't a text file."
        }
        let limit = 60_000
        return text.count > limit ? String(text.prefix(limit)) + "\n[cut at \(limit) characters of \(text.count)]" : text
    }

    static func list(_ url: URL) -> String {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return "No folder exists at \(url.path)."
        }
        let names = items.map { $0.lastPathComponent + (((try? $0.resourceValues(forKeys: Set(keys)))?.isDirectory ?? false) ? "/" : "") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let shown = names.prefix(300).joined(separator: "\n")
        return "\(url.path)\n" + shown + (names.count > 300 ? "\n[and \(names.count - 300) more]" : "")
    }

    static func edits(_ raw: String) -> [(find: String, replace: String)]? {
        guard let input = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let items = input["edits"] as? [[String: Any]]
        else { return nil }
        let edits = items.compactMap { item -> (find: String, replace: String)? in
            guard let find = item["find"] as? String, let replace = item["replace"] as? String else { return nil }
            return (find, replace)
        }
        return edits.count == items.count ? edits : nil
    }
}

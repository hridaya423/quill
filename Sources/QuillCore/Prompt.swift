import Foundation

public enum Mode: String, CaseIterable, Sendable {
    case guided
    case notes
}

public struct Request: Sendable {
    public var words: String
    public var path: String
    public var text: String
    public var selection: String?
    public var mode: Mode

    public init(words: String, path: String, text: String, selection: String?, mode: Mode) {
        self.words = words
        self.path = path
        self.text = text
        self.selection = selection
        self.mode = mode
    }
}

public func prompt(_ r: Request, canEditFiles: Bool) -> String {
    var lines = [
        "You are the co-writer inside Quill, a calm Markdown editor. The writer is looking at \(r.path) and just said:",
        "",
        "\"\(r.words)\"",
        "",
    ]
    if let s = r.selection, !s.isEmpty {
        lines += ["They have this passage selected, so \"this\" means it:", "<selection>", s, "</selection>", ""]
    }
    lines += ["The document right now:", "<document>", r.text, "</document>", ""]
    let how = canEditFiles
        ? "edit \(r.path) directly with your file editing tool"
        : "call the edit tool"
    switch r.mode {
    case .guided:
        lines += [
            "If they want the text changed, \(how). Make the smallest edits that do what they asked. Keep their voice. Leave every other word exactly as it is. Never touch other files and never run commands.",
            "If they asked a question or want your opinion, don't edit. Answer instead.",
            "Finish with a short plain-text reply for them: one sentence after an edit, up to three sentences for an opinion. No Markdown, no lists, no preamble.",
        ]
    case .notes:
        lines += [
            "Don't edit the document unless they explicitly ask you to change the text; if they do, \(how) with the smallest edits that do it.",
            "Otherwise reply with only a JSON array of margin notes and nothing else, like:",
            #"[{"quote": "exact words from the document", "note": "what you think and why, in one or two sentences"}]"#,
            "Each quote must be copied exactly from the document, 3 to 12 words long. Give at most 6 notes, most important first.",
        ]
    }
    return lines.joined(separator: "\n")
}

public struct MarginNote: Equatable, Sendable, Identifiable {
    public var id: Int
    public var range: NSRange
    public var quote: String
    public var note: String
}

public func notes(from reply: String, in text: String) -> [MarginNote]? {
    guard let open = reply.firstIndex(of: "["), let close = reply.lastIndex(of: "]"), open < close,
          let data = String(reply[open...close]).data(using: .utf8),
          let raw = try? JSONDecoder().decode([[String: String]].self, from: data)
    else { return nil }
    let doc = text as NSString
    var used: [NSRange] = []
    return raw.enumerated().compactMap { i, item in
        guard let quote = item["quote"]?.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty,
              let note = item["note"]?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty
        else { return nil }
        var r = doc.range(of: quote)
        if r.location == NSNotFound { r = doc.range(of: quote, options: [.caseInsensitive, .diacriticInsensitive]) }
        guard r.location != NSNotFound, !used.contains(where: { NSIntersectionRange($0, r).length > 0 }) else { return nil }
        used.append(r)
        return MarginNote(id: i, range: r, quote: quote, note: note)
    }
    .sorted { $0.range.location < $1.range.location }
}

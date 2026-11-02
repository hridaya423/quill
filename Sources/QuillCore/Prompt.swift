import Foundation

public enum Mode: String, CaseIterable, Sendable {
    case guided
    case notes
}

public struct Request: Sendable {
    public var words: String
    public var title: String
    public var path: String
    public var text: String
    public var selection: String?
    public var mode: Mode

    public init(words: String, title: String, path: String, text: String, selection: String?, mode: Mode) {
        self.words = words
        self.title = title
        self.path = path
        self.text = text
        self.selection = selection
        self.mode = mode
    }
}

public func prompt(_ r: Request, canEditFiles: Bool, voice: String? = nil, briefing: String? = nil) -> String {
    var lines: [String] = []
    if let briefing { lines += [briefing, "", "---", ""] }
    if let voice, !voice.isEmpty {
        lines += [
            "The writer's voice notes. They describe how this writer writes and what they want. When they disagree with the editorial guidance, follow the voice notes.",
            "<voice>", voice, "</voice>", "",
        ]
    }
    let target = canEditFiles ? "Your working copy of the note is \(r.path). " : ""
    lines += [
        "You are the co-writer inside Quill, a calm Markdown editor. The writer is looking at their note \"\(r.title)\". \(target)They just said:",
        "",
        "\"\(r.words)\"",
        "",
    ]
    if let s = r.selection, !s.isEmpty {
        lines += ["They have this passage selected, so \"this\" means it:", "<selection>", s, "</selection>", ""]
    }
    lines += ["The note right now:", "<document>", r.text, "</document>", ""]
    let how = canEditFiles
        ? "edit \(r.path) directly with your file editing tool. Edit only that file and never run commands"
        : "call the edit tool"
    switch r.mode {
    case .guided:
        lines += [
            "If they want the text changed, \(how). Make the smallest edits that do what they asked. Keep their voice. Leave every other word exactly as it is. The writer reviews each change and keeps or reverts it.",
            "If they asked a question or want your opinion, don't edit. Answer instead.",
            "Finish with a plain-text reply for them. After an edit: one short sentence, at most 12 words, naming what you changed; don't quote the new text or mention what you left alone. For an opinion: up to three sentences, specific and honest, the way a good editor talks. No Markdown, no lists, no preamble, no em dashes.",
        ]
    case .notes:
        lines += [
            "Don't edit the note unless they explicitly ask you to change the text; if they do, \(how) with the smallest edits that do it.",
            canEditFiles
                ? "Otherwise reply with only a JSON array of margin notes inside <notes></notes> tags and nothing else, like:"
                : "Otherwise call leave_notes once with your margin notes and write nothing else. Each note looks like:",
            canEditFiles
                ? #"<notes>[{"quote": "exact words from the document", "lens": "Cut", "note": "one direct sentence, at most 14 words"}]</notes>"#
                : #"{"quote": "exact words from the document", "lens": "Cut", "note": "one direct sentence, at most 14 words"}"#,
            "Each quote must be copied exactly from the document, 3 to 12 words long. The lens is one of: \(lenses.joined(separator: ", ")). Give at most 5 notes, most important first. Each note is one plain sentence of at most 14 words that tells the writer what to do, like \"Cut the second 'listens'; it lands better once.\" No hedging, no praise, no restating the quote, no em dashes.",
        ]
    }
    return lines.joined(separator: "\n")
}

public struct MarginNote: Equatable, Sendable, Identifiable {
    public var id: Int
    public var range: NSRange
    public var quote: String
    public var note: String
    public var lens: String?
}

public func readable(_ reply: String) -> String {
    var s = reply.replacingOccurrences(of: #"<(notes?|selection|document|voice)\b[^>]*>[\s\S]*?</\1>"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: #"</?[A-Za-z][\w-]*(\s[^>]*)?/?>"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: #"(?m)^\s*[-*]\s+"#, with: "• ", options: .regularExpression)
    s = s.replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: #"(?m)^[ \t]+|[ \t]+$"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

public func notes(from reply: String, in text: String) -> [MarginNote]? {
    var body = Substring(reply)
    if let start = reply.range(of: "<notes>"), let end = reply.range(of: "</notes>", range: start.upperBound..<reply.endIndex) {
        body = reply[start.upperBound..<end.lowerBound]
    }
    guard let open = body.firstIndex(of: "["), let close = body.lastIndex(of: "]"), open < close,
          let data = String(body[open...close]).data(using: .utf8),
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
        let lens = item["lens"].flatMap { l in lenses.first { $0.caseInsensitiveCompare(l) == .orderedSame } }
        return MarginNote(id: i, range: r, quote: quote, note: note, lens: lens)
    }
    .sorted { $0.range.location < $1.range.location }
}

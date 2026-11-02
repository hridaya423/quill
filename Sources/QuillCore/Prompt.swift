import Foundation
import NaturalLanguage

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
    public var sources: [Source]
    public var peers: [String]

    public struct Source: Sendable {
        public var url: String
        public var text: String

        public init(url: String, text: String) {
            self.url = url
            self.text = text
        }
    }

    public init(words: String, title: String, path: String, text: String, selection: String?, mode: Mode, sources: [Source] = [], peers: [String] = []) {
        self.words = words
        self.title = title
        self.path = path
        self.text = text
        self.selection = selection
        self.mode = mode
        self.sources = sources
        self.peers = peers
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
    let read = r.sources.filter { !$0.text.isEmpty }, unread = r.sources.filter { $0.text.isEmpty }
    if !read.isEmpty {
        lines += ["Quill fetched the pages linked in the note and the request. Treat them as the brief: use their facts, names, dates, and rules, and never invent details they don't contain."]
        for s in read { lines += ["<source url=\"\(s.url)\">", s.text, "</source>"] }
        lines += [""]
    }
    if !unread.isEmpty {
        lines += ["Quill couldn't open \(unread.map(\.url).joined(separator: ", ")). It may be private. If the request depends on it, say so in your reply and ask the writer to paste the text or share the link publicly.", ""]
    }
    lines += [
        "You can read the writer's other files when they point you at them. Their home folder is \(NSHomeDirectory()). A path they name, like \"Projects/site\" or \"@Projects/site\", is inside it unless it starts with /. Hidden folders and Library are off limits. Read with your file tools; don't run commands that change anything.",
        "When they name a folder or file, open it before you write a word: list the folder, then read the files that explain it, like the README and any plans or docs.",
        "Never invent what a file, folder, or project contains. If you can't find or open something they named, say so in one sentence and write nothing else.",
        "",
    ]
    let how = canEditFiles
        ? "edit \(r.path) directly with your file editing tool. Edit only that file"
        : "call the edit tool"
    if !r.peers.isEmpty {
        lines += [
            "Other co-writers (\(r.peers.joined(separator: ", "))) are answering this same request at the same time, and Quill stacks every answer in the note under the writer's own. Bring ideas the others are unlikely to: skip the obvious first answer. Fill and add; don't rewrite what the writer wrote.",
            "",
        ]
    }
    switch r.mode {
    case .guided:
        lines += [
            "If they want the text changed, \(how). Make the smallest edits that do what they asked. Keep their voice. Leave every other word exactly as it is. The writer reviews each change and keeps or reverts it.",
            "If they ask for new writing, like a draft, write it into the note in their voice, built only from what they gave you and what you read.",
            "If the note is an outline with empty slots, like blank bullets, \"...\", or labels such as \"Pros:\" with nothing after them, fill those slots in place. Keep the writer's own entries word for word, and match the outline's shape: the same bullets, labels, and nesting. If they ask for more, add new entries in that shape after theirs.",
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
    s = s.replacingOccurrences(of: #"<(notes?|selection|document|voice)\b[\s\S]*$"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: #"\[\s*\{\s*"(quote|lens|note)"[\s\S]*$"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: #"<[^>]*$"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: #"</?[A-Za-z][\w-]*(\s[^>]*)?/?>"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: #"(?m)^\s*[-*]\s+"#, with: "• ", options: .regularExpression)
    s = s.replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: #"(?m)^[ \t]+|[ \t]+$"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

public func crisp(_ reply: String, sentences limit: Int) -> String {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = reply
    var kept: [String] = []
    tokenizer.enumerateTokens(in: reply.startIndex..<reply.endIndex) { range, _ in
        kept.append(reply[range].trimmingCharacters(in: .whitespacesAndNewlines))
        return kept.count < limit
    }
    return kept.filter { !$0.isEmpty }.joined(separator: " ")
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

public func mentionToken(_ draft: String) -> Substring? {
    guard let at = draft.lastIndex(of: "@") else { return nil }
    if at > draft.startIndex, !draft[draft.index(before: at)].isWhitespace { return nil }
    let token = draft[draft.index(after: at)...]
    return token.contains(where: \.isWhitespace) ? nil : token
}

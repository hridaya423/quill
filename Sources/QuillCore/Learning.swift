import Foundation

public enum Outcome: String, Codable, Sendable {
    case kept, reverted, rewritten, undone
}

public struct Exchange: Codable, Equatable, Sendable {
    public var request: String
    public var before: String
    public var proposed: String
    public var final: String
    public var outcome: Outcome

    public init(request: String, before: String, proposed: String, final: String, outcome: Outcome) {
        self.request = request
        self.before = before
        self.proposed = proposed
        self.final = final
        self.outcome = outcome
    }
}

private func words(_ s: String) -> Set<Substring> {
    Set(s.lowercased().split { !$0.isLetter && !$0.isNumber })
}

private func similarity(_ a: String, _ b: String) -> Double {
    let x = words(a), y = words(b)
    guard !x.isEmpty || !y.isEmpty else { return 1 }
    return Double(x.intersection(y).count) / Double(x.union(y).count)
}

public func exchanges(request: String, before: String, proposed: String, kept: String) -> [Exchange] {
    let a = before.components(separatedBy: "\n\n"), b = proposed.components(separatedBy: "\n\n")
    let now = kept.components(separatedBy: "\n\n")
    let diff = b.difference(from: a)
    var removed: [Int: String] = [:], inserted: [Int: String] = [:]
    for change in diff {
        switch change {
        case .remove(let i, let p, _): removed[i] = p
        case .insert(let i, let p, _): inserted[i] = p
        }
    }
    var used = Set<Int>()
    return inserted.keys.sorted().map { i in
        let new = inserted[i]!
        let old = removed.min { abs($0.key - i) < abs($1.key - i) && !used.contains($0.key) }.map { kv -> String in
            used.insert(kv.key)
            return kv.value
        } ?? ""
        let outcome: Outcome
        var final = new
        if now.contains(new) {
            outcome = .kept
        } else if !old.isEmpty, now.contains(old) {
            outcome = .reverted
            final = old
        } else {
            outcome = .rewritten
            final = now.max { similarity($0, new) < similarity($1, new) } ?? ""
        }
        return Exchange(request: request, before: old, proposed: new, final: final, outcome: outcome)
    }
}

public enum VoiceSection: String, CaseIterable, Sendable {
    case mine = "My rules"
    case learned = "Learned"
    case measured = "Measured"
}

public let voiceIntro = """
# My voice

Quill reads this note before every edit. Change anything you like. Quill never touches “My rules”, rewrites “Learned” as it watches what you keep and undo, and refreshes “Measured” from your notes.
"""

public func section(_ s: VoiceSection, in doc: String) -> String? {
    let lines = doc.components(separatedBy: "\n")
    guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## " + s.rawValue }) else { return nil }
    let rest = lines[(start + 1)...]
    let end = rest.firstIndex { $0.hasPrefix("## ") } ?? lines.endIndex
    return lines[(start + 1)..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

public func voiceDocument(existing: String?, learned: String? = nil, measured: [String]? = nil, source: String? = nil) -> String {
    let mine = existing.flatMap { section(.mine, in: $0) } ?? "- Add your own rules here. Quill treats them as yours and never edits them."
    let learnedText = learned ?? existing.flatMap { section(.learned, in: $0) } ?? "- Nothing yet. Quill learns from the edits you keep, undo, and rewrite."
    var measuredText = existing.flatMap { section(.measured, in: $0) } ?? ""
    if let measured {
        measuredText = measured.map { "- " + $0 }.joined(separator: "\n")
        if let source { measuredText += "\n\n_\(source)_" }
    }
    var parts = [voiceIntro, "## My rules\n\n" + mine, "## Learned\n\n" + learnedText]
    if !measuredText.isEmpty { parts.append("## Measured\n\n" + measuredText) }
    return parts.joined(separator: "\n\n") + "\n"
}

public func distillPrompt(voice: String, exchanges: [Exchange]) -> String {
    let evidence = exchanges.enumerated().map { i, e in
        """
        <exchange n="\(i + 1)" outcome="\(e.outcome.rawValue)">
        request: \(e.request)
        original: \(e.before)
        quill proposed: \(e.proposed)
        writer's final text: \(e.final)
        </exchange>
        """
    }.joined(separator: "\n")
    return """
    You maintain a writer's voice notes for Quill, their writing app. Do not edit any files and do not run commands. Reply with text only.

    Here are their current voice notes:
    <voice>
    \(voice)
    </voice>

    Here is what happened to Quill's recent edits. "kept" means they accepted it. "undone" and "reverted" mean they rejected it. "rewritten" means they changed Quill's text by hand, so their final text shows what they wanted.
    \(evidence)

    Write the new contents of the "Learned" section and nothing else: a Markdown list of at most 12 rules about how this writer wants their prose edited. Each rule is one plain sentence followed by a short quote from their own final text as evidence, formatted as: - Rule sentence. Example: “their words”.
    Keep existing learned rules unless the evidence contradicts them. Merge duplicates. Only write rules the evidence supports; never guess. Never contradict the writer's own rules. Do not use em dashes. Output only the list.
    """
}

public func learnedRules(from reply: String) -> String? {
    let lines = reply.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
    guard !lines.isEmpty else { return nil }
    return lines.prefix(12).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
}

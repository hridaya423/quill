import Foundation

public struct Tell: Equatable, Sendable, Hashable {
    public var kind: String
    public var phrase: String
}

private func pattern(_ p: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
}

private let rules: [(String, NSRegularExpression)] = [
    ("AI vocabulary", pattern(#"\b(delv(e|es|ed|ing)|tapestr(y|ies)|testament to|multifaceted|realm|interplay|underscor(e|es|ed|ing)|leverag(e|es|ed|ing)|it'?s worth noting|game[- ]changer|unlock(s|ed|ing)? the)\b"#)),
    ("Landscape opener", pattern(#"\bin today'?s [a-z -]{0,30}(landscape|world|age|era)\b"#)),
    ("Em dash", pattern(#"—|–| -- "#)),
    ("Negative parallelism", pattern(#"(\bnot|n['’]t) (just|merely|simply) [^.!?\n]{1,60}?,? but( also)?\b|\b(it'?s|it is|this is|that'?s) not (about )?[^.!?\n]{1,40}?[,;—] (it'?s|it is)\b"#)),
    ("Significance inflation", pattern(#"\b(serves as an?|stands as an?|pivotal (moment|role)|indelible mark|evolving landscape|plays? a (crucial|vital|key) role)\b"#)),
    ("Filler", pattern(#"\b(in order to|due to the fact that|at this point in time|has the ability to|it is important to note|it should be noted)\b"#)),
    ("Chatbot artifact", pattern(#"\b(i hope this helps|great question|let'?s dive in|here'?s the thing|let'?s be honest|here'?s what you need to know)\b|\b(certainly|of course|absolutely)!"#)),
    ("Generic ending", pattern(#"\b(the future looks bright|exciting times (lie|are) ahead|only time will tell|the possibilities are endless)\b"#)),
    ("Whether summary", pattern(#"\bwhether you'?re an? [^.!?\n]{1,40} or\b"#)),
    ("Promotional", pattern(#"\b(nestled|breathtaking|world-class|must-visit|cutting-edge|seamless(ly)?)\b"#)),
]

private let tierTwo = pattern(#"\b(crucial|pivotal|vibrant|robust|seamless|foster(s|ed|ing)?|enhanc(e|es|ed|ing)|showcas(e|es|ed|ing)|notably|moreover|furthermore|utiliz(e|es|ed|ing)|align(s|ed)? with)\b"#)

public func tells(in text: String) -> [Tell] {
    let ns = text as NSString
    let all = NSRange(location: 0, length: ns.length)
    var found: [Tell] = []
    for (kind, rx) in rules {
        for m in rx.matches(in: text, range: all) {
            found.append(Tell(kind: kind, phrase: ns.substring(with: m.range)))
        }
    }
    for paragraph in text.components(separatedBy: "\n\n") {
        let p = paragraph as NSString
        let hits = tierTwo.matches(in: paragraph, range: NSRange(location: 0, length: p.length))
        if hits.count >= 2 {
            found.append(Tell(kind: "AI vocabulary cluster", phrase: hits.map { p.substring(with: $0.range) }.joined(separator: ", ")))
        }
    }
    return found
}

public func introducedTells(before: String, after: String, allowing habits: Set<String> = []) -> [Tell] {
    var budget: [String: Int] = [:]
    for t in tells(in: before) { budget[t.kind + "|" + t.phrase.lowercased(), default: 0] += 1 }
    var introduced: [Tell] = []
    for t in tells(in: after) {
        if habits.contains(t.kind) { continue }
        let key = t.kind + "|" + t.phrase.lowercased()
        if let n = budget[key], n > 0 { budget[key] = n - 1 } else { introduced.append(t) }
    }
    return introduced
}

public func habitualTells(_ texts: [String]) -> Set<String> {
    var counts: [String: Int] = [:]
    for text in texts where isWriting(text) {
        for tell in tells(in: prose(from: text)) { counts[tell.kind, default: 0] += 1 }
    }
    return Set(counts.filter { $0.value >= 3 }.keys)
}

public func changedParagraphs(base: String, proposed: String) -> (before: String, after: String) {
    let a = base.components(separatedBy: "\n\n"), b = proposed.components(separatedBy: "\n\n")
    let diff = b.difference(from: a)
    var removed: [String] = [], inserted: [String] = []
    for change in diff {
        switch change {
        case .remove(_, let p, _): removed.append(p)
        case .insert(_, let p, _): inserted.append(p)
        }
    }
    return (removed.joined(separator: "\n\n"), inserted.joined(separator: "\n\n"))
}

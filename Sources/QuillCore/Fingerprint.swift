import Foundation

public struct Fingerprint: Codable, Equatable, Sendable {
    public var words = 0
    public var sentences = 0
    public var sentenceMean = 0.0
    public var sentenceSpread = 0.0
    public var shortShare = 0.0
    public var longShare = 0.0
    public var contractions = 0.0
    public var lowercaseStarts = 0.0
    public var andButStarts = 0.0
    public var firstPerson = 0.0
    public var punctuation: [String: Double] = [:]
    public var habits: [String: Double] = [:]
    public var avoided: [String] = []

    public static let marks: [(String, String)] = [
        ("em dashes", "—"), ("semicolons", ";"), ("colons", ":"), ("parentheses", "("),
        ("exclamation marks", "!"), ("question marks", "?"), ("ellipses", "..."),
    ]

    public static let habitWords = [
        "basically", "actually", "really", "just", "literally", "honestly", "kinda", "kind of", "sort of",
        "gonna", "wanna", "like", "pretty", "super", "maybe", "probably", "i think", "i guess", "so",
        "anyway", "stuff", "things", "very", "quite", "lol", "tbh", "idk", "rn", "ngl", "etc",
    ]

    public static let formalWords = [
        "moreover", "furthermore", "additionally", "utilize", "leverage", "delve", "crucial", "pivotal",
        "robust", "seamless", "foster", "enhance", "showcase", "notably", "therefore", "thus", "hence",
        "whereas", "comprehensive", "facilitate", "endeavor", "myriad", "plethora", "tapestry",
    ]
}

public func isWriting(_ markdown: String) -> Bool {
    !markdown.contains("excalidraw-plugin") && !markdown.contains("EXCALIDRAW VIEW")
}

public func prose(from markdown: String, lists: Bool = true) -> String {
    var out: [String] = []
    var fence = false
    var front = false
    for (i, raw) in markdown.components(separatedBy: "\n").enumerated() {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if i == 0, line == "---" { front = true; continue }
        if front { if line == "---" { front = false }; continue }
        if line.hasPrefix("```") { fence.toggle(); continue }
        if fence || line.hasPrefix("#") || line.hasPrefix("|") || line.hasPrefix("![") || line.hasPrefix("<") { continue }
        if !lists, line.range(of: #"^([-*+]|\d+[.)])\s"#, options: .regularExpression) != nil { continue }
        var t = line
        t = t.replacingOccurrences(of: #"^([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[\[([^\]|]*\|)?([^\]]*)\]\]"#, with: "$2", options: .regularExpression)
        t = t.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"`[^`]*`"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[*_]{1,3}"#, with: "", options: .regularExpression)
        out.append(t)
    }
    return out.joined(separator: "\n")
}

public func sentences(in text: String) -> [String] {
    var result: [String] = []
    text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), s.split(separator: " ").count >= 2 else { return }
        for line in s.components(separatedBy: "\n") where line.split(separator: " ").count >= 2 {
            result.append(line.trimmingCharacters(in: .whitespaces))
        }
    }
    return result
}

private func count(_ needle: String, in haystack: String) -> Int {
    if needle.contains(" ") || needle.count > 1 && !needle.allSatisfy(\.isLetter) {
        return haystack.components(separatedBy: needle).count - 1
    }
    if !needle.allSatisfy(\.isLetter) { return haystack.filter { String($0) == needle }.count }
    let rx = try! NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b")
    return rx.numberOfMatches(in: haystack, range: NSRange(location: 0, length: (haystack as NSString).length))
}

public func fingerprint(_ texts: [String]) -> Fingerprint {
    var f = Fingerprint()
    let texts = texts.filter(isWriting)
    let paragraphs = texts.map { prose(from: $0, lists: false) }.joined(separator: "\n\n")
    let body = paragraphs.split(whereSeparator: \.isWhitespace).count >= 400
        ? paragraphs
        : texts.map { prose(from: $0) }.joined(separator: "\n\n")
    let all = sentences(in: body)
    let lengths = all.map { Double($0.split(whereSeparator: \.isWhitespace).count) }
    let wordCount = body.split(whereSeparator: \.isWhitespace).count
    guard wordCount > 0, !lengths.isEmpty else { return f }
    f.words = wordCount
    f.sentences = all.count
    f.sentenceMean = lengths.reduce(0, +) / Double(lengths.count)
    let variance = lengths.map { ($0 - f.sentenceMean) * ($0 - f.sentenceMean) }.reduce(0, +) / Double(lengths.count)
    f.sentenceSpread = variance.squareRoot()
    f.shortShare = Double(lengths.filter { $0 <= 6 }.count) / Double(lengths.count)
    f.longShare = Double(lengths.filter { $0 >= 25 }.count) / Double(lengths.count)
    let per1k = 1000 / Double(wordCount)
    let lower = body.lowercased()
    let contraction = try! NSRegularExpression(pattern: #"\b[a-z]+'(t|re|ve|ll|d|m)\b|\b(it|that|there|what|he|she|let|here|who)'s\b"#, options: .caseInsensitive)
    let apostrophes = body.replacingOccurrences(of: "’", with: "'")
    f.contractions = Double(contraction.numberOfMatches(in: apostrophes, range: NSRange(location: 0, length: (apostrophes as NSString).length))) * per1k
    f.lowercaseStarts = Double(all.filter { $0.first?.isLowercase == true }.count) / Double(all.count)
    f.andButStarts = Double(all.filter { $0.hasPrefix("And ") || $0.hasPrefix("But ") }.count) / Double(all.count)
    f.firstPerson = Double(count("i", in: lower) + count("i'm", in: lower) + count("my", in: lower)) * per1k
    for (name, mark) in Fingerprint.marks {
        f.punctuation[name] = Double(count(mark, in: body)) * per1k
    }
    for w in Fingerprint.habitWords {
        let n = count(w, in: lower)
        if n > 0 { f.habits[w] = Double(n) * per1k }
    }
    f.avoided = Fingerprint.formalWords.filter { count($0, in: lower) == 0 }
    return f
}

public func distance(_ a: Fingerprint, _ b: Fingerprint) -> Double {
    func d(_ x: Double, _ y: Double, _ scale: Double) -> Double { min(3, abs(x - y) / scale) }
    var total = 0.0
    total += d(a.sentenceMean, b.sentenceMean, 4)
    total += d(a.sentenceSpread, b.sentenceSpread, 3)
    total += d(a.shortShare, b.shortShare, 0.1)
    total += d(a.longShare, b.longShare, 0.1)
    total += d(a.contractions, b.contractions, 8)
    total += d(a.lowercaseStarts, b.lowercaseStarts, 0.1)
    total += d(a.andButStarts, b.andButStarts, 0.05)
    for (name, _) in Fingerprint.marks {
        total += d(a.punctuation[name] ?? 0, b.punctuation[name] ?? 0, 3)
    }
    let words = Set(a.habits.keys).union(b.habits.keys)
    for w in words { total += d(a.habits[w] ?? 0, b.habits[w] ?? 0, 3) / 2 }
    let introduced = Set(a.avoided).subtracting(b.avoided).count
    total += Double(introduced)
    return total
}

func share(_ x: Double) -> String {
    switch x {
    case 0.9...: "Nearly all"
    case 0.6..<0.9: "Most"
    case 0.4..<0.6: "About half of the"
    case 0.25..<0.4: "About a third of the"
    case 0.15..<0.25: "About one in five"
    default: "A few"
    }
}

public func describe(_ f: Fingerprint) -> [String] {
    guard f.sentences > 0 else { return [] }
    var lines: [String] = []
    var length = String(format: "Sentences average %.0f words", f.sentenceMean)
    if f.sentenceSpread >= 3 { length += String(format: " and swing by about %.0f either way", f.sentenceSpread) }
    lines.append(length + ".")
    if f.shortShare >= 0.15 { lines.append("\(share(f.shortShare)) sentences are six words or fewer.") }
    if f.longShare >= 0.05 { lines.append("\(share(f.longShare)) sentences run past 25 words.") }
    lines.append(f.contractions >= 10
                 ? String(format: "Contractions come easily, about %.0f per 1,000 words.", f.contractions)
                 : "Contractions are rare.")
    if f.lowercaseStarts >= 0.15 {
        lines.append("\(share(f.lowercaseStarts)) sentences start lowercase. That's a choice, so keep it.")
    }
    let marks = Fingerprint.marks.map { ($0.0, f.punctuation[$0.0] ?? 0) }
    let used = marks.filter { $0.1 >= 1 }.sorted { $0.1 > $1.1 }
    let unused = marks.filter { $0.1 < 0.3 }.map(\.0)
    if !used.isEmpty {
        lines.append("Favourite punctuation: " + used.prefix(3).map { String(format: "%@ (%.0f per 1,000 words)", $0.0, $0.1) }.joined(separator: ", ") + ".")
    }
    if !unused.isEmpty {
        lines.append("Almost never uses: " + unused.joined(separator: ", ") + ".")
    }
    let habits = f.habits.sorted { $0.value > $1.value }.prefix(8).map(\.key)
    if !habits.isEmpty {
        lines.append("Habit words: " + habits.map { "“\($0)”" }.joined(separator: ", ") + ".")
    }
    if !f.avoided.isEmpty {
        lines.append("Never writes: " + f.avoided.prefix(12).joined(separator: ", ") + ".")
    }
    return lines
}

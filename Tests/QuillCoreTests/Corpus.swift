import Foundation
import Testing
@testable import QuillCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["QUILL_CORPUS"] != nil))
func corpusReport() throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUILL_CORPUS"]!)
    let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])!
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "md" && !$0.lastPathComponent.contains("excalidraw") }
    let texts = files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    let f = fingerprint(texts)
    print("files \(texts.count) words \(f.words) sentences \(f.sentences)")
    describe(f).forEach { print("  " + $0) }
    var hits: [String: Int] = [:]
    for t in texts { for tell in tells(in: prose(from: t)) { hits[tell.kind, default: 0] += 1 } }
    print("tells in own writing:", hits.sorted { $0.value > $1.value })
}

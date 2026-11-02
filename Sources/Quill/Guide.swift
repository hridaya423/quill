import Foundation
import QuillCore

enum Guide {
    static var installed: URL? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return [".agents/skills/prose", ".claude/skills/prose"].map { home.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.appending(path: "SKILL.md").path) }
    }

    static var skill: URL? { installed ?? Brand.url("Prose") }

    static func briefing() -> String {
        guard let skill, let text = try? String(contentsOf: skill.appending(path: "SKILL.md"), encoding: .utf8) else { return editorialGuide }
        let body = text.hasPrefix("---") ? text.components(separatedBy: "\n---").dropFirst().joined(separator: "\n---") : text
        return editorialGuide + """


        # The writer's own writing guide

        The writer uses this guide for all their writing. Follow it for every word you write, along with the editorial guidance above. \
        Its reference files are in \(skill.path)/references; read one when the guide sends your task to it.

        """ + body
    }
}

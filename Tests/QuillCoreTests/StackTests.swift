import Testing
@testable import QuillCore

let brainstorm = """
# Hackathon ideas

- AR study buddy
  - Pros: works offline
  - Cons:
-
-
"""

@Test func twoModelsFillingTheSameBlanksBothLand() {
    let claude = brainstorm.replacingOccurrences(of: "-\n-", with: "- Voice-first lecture notes\n  - Pros: hands-free\n  - Cons: noisy rooms\n-")
    let codex = brainstorm.replacingOccurrences(of: "-\n-", with: "- Peer-review marketplace\n  - Pros: network effects\n  - Cons: cold start\n-")
    let out = stack(base: brainstorm, versions: [claude, codex])
    #expect(out.contains("- Voice-first lecture notes"))
    #expect(out.contains("- Peer-review marketplace"))
    #expect(out.contains("- AR study buddy\n  - Pros: works offline"))
    #expect(out.range(of: "Voice-first")!.lowerBound < out.range(of: "Peer-review")!.lowerBound)
}

@Test func filledLabelsStackUnderTheWritersEntry() {
    let a = brainstorm.replacingOccurrences(of: "  - Cons:\n", with: "  - Cons: needs a camera\n")
    let b = brainstorm.replacingOccurrences(of: "  - Cons:\n", with: "  - Cons: battery drain\n")
    let out = stack(base: brainstorm, versions: [a, b])
    #expect(out.contains("  - Cons: needs a camera\n  - Cons: battery drain\n"))
}

@Test func conflictingRewritesOfTheWritersTextKeepThePrimary() {
    let a = brainstorm.replacingOccurrences(of: "AR study buddy", with: "AR tutor")
    let b = brainstorm.replacingOccurrences(of: "AR study buddy", with: "Study buddy in AR")
    let out = stack(base: brainstorm, versions: [a, b])
    #expect(out.contains("- AR tutor\n"))
    #expect(!out.contains("Study buddy in AR"))
}

@Test func separateEditsFromEachModelAllApply() {
    let a = brainstorm.replacingOccurrences(of: "# Hackathon ideas", with: "# Hackathon ideas for Luma")
    let b = brainstorm + "\n\n## Next step\nPick one by Friday."
    let out = stack(base: brainstorm, versions: [a, b])
    #expect(out.hasPrefix("# Hackathon ideas for Luma"))
    #expect(out.hasSuffix("Pick one by Friday."))
}

@Test func identicalFillsAreNotRepeated() {
    let a = brainstorm.replacingOccurrences(of: "  - Cons:\n", with: "  - Cons: battery drain\n")
    #expect(stack(base: brainstorm, versions: [a, a]) == a)
}


@Test func fillsUnderTheWritersItemStayUnderIt() {
    let base = "## Ideas\n\n- Quiz at check-in\n  - Pros:\n  - Cons:\n-\n  - Pros:\n  - Cons:\n"
    let claude = "## Ideas\n\n- Quiz at check-in\n  - Pros: easy opener\n  - Cons: slows check-in\n- Blotter swap\n  - Pros: meet people\n  - Cons: put on the spot\n"
    let codex = "## Ideas\n\n- Quiz at check-in\n  - Pros: helps beginners\n  - Cons: narrows choices\n- Before and after blend\n  - Pros: shows one change\n  - Cons: needs prep\n"
    let out = stack(base: base, versions: [claude, codex])
    #expect(out == "## Ideas\n\n- Quiz at check-in\n  - Pros: easy opener\n  - Pros: helps beginners\n  - Cons: slows check-in\n  - Cons: narrows choices\n- Blotter swap\n  - Pros: meet people\n  - Cons: put on the spot\n- Before and after blend\n  - Pros: shows one change\n  - Cons: needs prep\n")
}

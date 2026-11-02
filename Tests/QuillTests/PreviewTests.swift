import AppKit
import Testing
@testable import Quill

@MainActor
struct PreviewTests {
    func editor(_ text: String) -> (QuillTextView, NSWindow) {
        Brand.register()
        let (scroll, view) = QuillTextView.make()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        view.string = text
        view.restyle(NSRange(location: 0, length: (text as NSString).length))
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        view.layoutSubtreeIfNeeded()
        return (view, window)
    }

    func click(_ view: QuillTextView, _ window: NSWindow, on phrase: String) {
        let r = (view.string as NSString).range(of: phrase)
        let seg = view.segments(r).first!
        let point = view.convert(NSPoint(x: seg.midX, y: seg.midY), to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        view.mouseDown(with: event)
    }

    @Test func clickingABoxChecksItAndUndoUnchecksIt() {
        let (view, window) = editor("- [ ] call Sam\n\nend")
        click(view, window, on: "[ ]")
        #expect(view.string == "- [x] call Sam\n\nend")
        view.undoManager?.undo()
        #expect(view.string == "- [ ] call Sam\n\nend")
    }

    @Test func clickingAWikilinkOffTheCaretLineFollowsIt() {
        let (view, window) = editor("See [[Voice|my voice]] here.\n\nend")
        var followed: String?
        view.onOpenNote = { followed = $0 }
        click(view, window, on: "my voice")
        #expect(followed == "Voice")
    }

    @Test func markersShowOnlyOnTheCaretLine() {
        let (view, _) = editor("a **b** c\n\nend")
        let storage = view.textStorage!
        #expect((storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize ?? 20 < 1)
        view.setSelectedRange(NSRange(location: 1, length: 0))
        #expect((storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize ?? 0 > 10)
    }

    @Test func doubleBracketCompletesNoteTitlesAndCloses() {
        let (view, _) = editor("See ")
        view.noteTitles = { ["Groceries", "Typography", "pitch"] }
        view.insertText("[[Ty", replacementRange: view.selectedRange())
        let partial = view.rangeForUserCompletion
        var index = 0
        let found = view.completions(forPartialWordRange: partial, indexOfSelectedItem: &index)
        #expect(found == ["Typography"])
        view.insertCompletion("Typography", forPartialWordRange: partial, movement: NSTextMovement.return.rawValue, isFinal: true)
        #expect(view.string == "See [[Typography]]")
    }
}

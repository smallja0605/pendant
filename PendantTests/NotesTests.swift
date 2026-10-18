import Foundation
import Testing
@testable import Pendant

struct NoteMarkdownTests {
    @Test func titleSkipsMarkersAndBlankLines() {
        #expect(NoteMarkdown.title(of: "\n\n**買牛奶** 和蛋\n第二行") == "買牛奶 和蛋")
        #expect(NoteMarkdown.title(of: "- [ ] 待辦") == "待辦")
        #expect(NoteMarkdown.title(of: "   \n") == "")
        #expect(NoteMarkdown.title(of: String(repeating: "a", count: 100)).count == 40)
    }

    @Test func pinnedNotesComeFirstThenNewest() {
        let now = Date()
        let old = Note(text: "old", pinned: false, updatedAt: now.addingTimeInterval(-100))
        let new = Note(text: "new", pinned: false, updatedAt: now)
        let pinned = Note(text: "pinned", pinned: true, updatedAt: now.addingTimeInterval(-500))
        #expect(NoteMarkdown.sorted([old, new, pinned]).map(\.text) == ["pinned", "new", "old"])
    }

    @Test func returnContinuesListsAndTodos() {
        #expect(NoteMarkdown.continuation(of: "- item") == "- ")
        #expect(NoteMarkdown.continuation(of: "  - [x] done") == "  - [ ] ")
        #expect(NoteMarkdown.continuation(of: "plain") == nil)
        #expect(NoteMarkdown.isEmptyListLine("- "))
        #expect(NoteMarkdown.isEmptyListLine("- [ ]"))
        #expect(!NoteMarkdown.isEmptyListLine("- x"))
    }

    @Test func checkboxToggles() {
        #expect(NoteMarkdown.togglingCheckbox(in: "- [ ] a") == "- [x] a")
        #expect(NoteMarkdown.togglingCheckbox(in: "- [x] a") == "- [ ] a")
        #expect(NoteMarkdown.togglingCheckbox(in: "no box") == "no box")
        #expect(NoteMarkdown.isChecked("- [X] a") && !NoteMarkdown.isChecked("- [ ] a"))
        #expect(NoteMarkdown.checkboxRange(in: "  - [ ] a") == 4..<7)
    }

    @Test func formattingCommands() {
        #expect(NoteMarkdown.toggledBold("hi") == "**hi**")
        #expect(NoteMarkdown.toggledBold("**hi**") == "hi")
        #expect(NoteMarkdown.toggledBold("") == "**粗體**")
        #expect(NoteMarkdown.togglingPrefix("- ", on: "a\nb") == "- a\n- b")
        #expect(NoteMarkdown.togglingPrefix("- ", on: "- a\n- b") == "a\nb")
    }
}

struct ShelfRulesTests {
    @Test func duplicateNamesGetANumber() {
        #expect(ShelfRules.uniqueName("a.txt", existing: []) == "a.txt")
        #expect(ShelfRules.uniqueName("a.txt", existing: ["a.txt"]) == "a 2.txt")
        #expect(ShelfRules.uniqueName("a.txt", existing: ["a.txt", "a 2.txt"]) == "a 3.txt")
        #expect(ShelfRules.uniqueName("folder", existing: ["folder"]) == "folder 2")
    }

    @Test func autoClearRules() {
        let now = Date()
        let old = ShelfItem(name: "old", addedAt: now.addingTimeInterval(-8 * 86_400))
        let fresh = ShelfItem(name: "fresh", addedAt: now.addingTimeInterval(-86_400))
        #expect(ShelfRules.expired([old, fresh], days: 7, now: now).map(\.name) == ["old"])
        #expect(ShelfRules.rebooted(lastBoot: now.addingTimeInterval(-1000), currentBoot: now))
        #expect(!ShelfRules.rebooted(lastBoot: now, currentBoot: now.addingTimeInterval(1)))
        #expect(!ShelfRules.rebooted(lastBoot: nil, currentBoot: now))
    }
}

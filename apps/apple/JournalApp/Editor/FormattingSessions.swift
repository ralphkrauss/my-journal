import SwiftUI

/// What Insert Image, Insert Link and the Format panel act on: the selection when they were chosen. An image that
/// arrives later still goes there, and leaves the person's selection, focus and scrolling where they are if they have
/// moved on (docs/design/several-photos-2026-10-03.md).
#if os(macOS)
    extension NativeEditor.Coordinator {
        func formattingSession() -> ((EditorCommand) -> Void)? {
            if let cellSession = tables?.cellFormattingSession(fallback: { [weak self] command in
                self?.perform(command)
            }) {
                return cellSession
            }
            guard let view, parent.editable else { return nil }
            let id = parent.itemID
            var generation = sessionGeneration
            var range = view.selectedRange()
            var document = parent.document
            var text = view.string
            return { [weak self] command in
                guard let self, let view = self.view, self.parent.itemID == id, self.parent.editable else { return }
                if self.sessionGeneration != generation || self.parent.document != document {
                    // Formatting applies only to the text it was chosen for, but an image that finishes
                    // importing after further writing still goes where it was placed.
                    guard case .image = command else { return }
                    range = TextRanges.insertionPoint(following: range, from: text, to: view.string)
                }
                guard NSMaxRange(range) <= view.string.utf16.count else { return }
                // An image arriving after the person moved on goes where it was placed, and leaves their
                // selection, focus and scrolling as they are.
                let person = view.selectedRange()
                let moved: Bool
                if case .image = command { moved = person != range } else { moved = false }
                let length = view.string.utf16.count
                let start = range.location
                view.setSelectedRange(range)
                self.insertingQuietly = moved
                self.perform(command)
                self.insertingQuietly = false
                range = view.selectedRange()
                if moved {
                    view.setSelectedRange(
                        TextRanges.shifted(person, by: view.string.utf16.count - length, at: start))
                }
                document = self.parent.document
                generation = self.sessionGeneration
                text = view.string
            }
        }
    }
#else
    extension NativeEditor.Coordinator {
        func formattingSession() -> ((EditorCommand) -> Void)? {
            if let cellSession = tables?.cellFormattingSession(fallback: { [weak self] command in
                self?.perform(command)
            }) {
                return cellSession
            }
            guard let view, parent.editable else { return nil }
            let id = parent.itemID
            var generation = sessionGeneration
            var range = view.selectedRange
            var document = parent.document
            var text = view.textStorage.string
            return { [weak self] command in
                guard let self, let view = self.view, self.parent.itemID == id, self.parent.editable else { return }
                if self.sessionGeneration != generation || self.parent.document != document {
                    // Formatting applies only to the text it was chosen for, but an image that finishes
                    // importing after further writing still goes where it was placed.
                    guard case .image = command else { return }
                    range = TextRanges.insertionPoint(following: range, from: text, to: view.textStorage.string)
                }
                guard NSMaxRange(range) <= view.textStorage.length else { return }
                // An image arriving after the person moved on goes where it was placed, and leaves their
                // selection, keyboard and scrolling as they are.
                let person = view.selectedRange
                let moved: Bool
                if case .image = command { moved = person != range } else { moved = false }
                let length = view.textStorage.length
                let start = range.location
                view.selectedRange = range
                self.insertingQuietly = moved
                self.perform(command)
                self.insertingQuietly = false
                range = view.selectedRange
                if moved {
                    view.selectedRange = TextRanges.shifted(person, by: view.textStorage.length - length, at: start)
                    self.revealCaretAfterEdit()
                }
                document = self.parent.document
                generation = self.sessionGeneration
                text = view.textStorage.string
            }
        }
    }
#endif

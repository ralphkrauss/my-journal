---
id: editing-rules
title: Editing rules (Apple)
spec: flows/editing-rules.md
features: [entry-title, entry-body, inline-formatting, paragraph-styles, lists, checklists, list-indentation, block-quotes, code-blocks, horizontal-rules, tables, links, inert-links, insert-image, image-actions, markdown-as-you-type, source-view, paste-and-drop, copy-to-other-apps, undo-redo, spelling-and-substitutions, autosave]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Editor/NativeEditor.swift
  - apps/apple/JournalApp/Editor/NativeTextView.swift
  - apps/apple/JournalApp/Editor/JournalWritingView.swift
  - apps/apple/JournalApp/Editor/EntryTitleEditor.swift
  - apps/apple/JournalApp/Editor/ListEditing.swift
  - apps/apple/JournalApp/Editor/ListIndentation.swift
  - apps/apple/JournalApp/Editor/ListLayout.swift
  - apps/apple/JournalApp/Editor/HiddenMarkers.swift
  - apps/apple/JournalApp/Editor/StructuredKeyboard.swift
  - apps/apple/JournalApp/Editor/KeyboardFormatting.swift
  - apps/apple/JournalApp/Editor/MarkdownShortcutEditing.swift
  - apps/apple/JournalApp/Editor/MarkdownEditing.swift
  - apps/apple/JournalApp/Editor/SourceFormatting.swift
  - apps/apple/JournalApp/Editor/InlineTasks.swift
  - apps/apple/JournalApp/Editor/InlineTables.swift
  - apps/apple/JournalApp/Editor/LinkEditing.swift
  - apps/apple/JournalApp/Editor/PastedRichText.swift
  - apps/apple/JournalApp/Editor/PastedTextInsertion.swift
  - apps/apple/JournalApp/Editor/InsertedText.swift
  - apps/apple/JournalApp/Editor/DocumentUndo.swift
  - apps/apple/JournalApp/Editor/ExternalEdits.swift
  - apps/apple/JournalApp/Editor/EditorReading.swift
  - apps/apple/JournalApp/Editor/SelectionReveal.swift
  - apps/apple/JournalApp/Editor/TypingRoom.swift
  - apps/apple/JournalApp/Editor/RichText.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/MarkdownDocument.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/MarkdownReader.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/MarkdownWriter.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/DocumentTable.swift
  - docs/design/list-markers-2026-10-03.md
  - docs/design/list-indentation-2026-10-04.md
  - docs/design/checklists-2026-10-03.md
  - docs/design/pasted-text.md
  - docs/design/menus-and-popovers.md
---

# Editing rules (Apple)

How the spec's [Editing rules](../../../flows/editing-rules.md) are implemented on iPhone, iPad and Mac. The rules themselves are platform neutral and are not repeated; this page says which code owns each group of them, what is shared and what differs by toolkit (`NSTextView` on the Mac, `UITextView` on iPhone and iPad). Where a group has its own page it is linked: [markdown-as-you-type.md](markdown-as-you-type.md), [edit-table.md](edit-table.md), [insert-image.md](insert-image.md), [image-actions.md](image-actions.md), [save-entry.md](save-entry.md). The screens it acts in are [entry-editor.md](../screens/entry-editor.md), [format-sheet.md](../screens/format-sheet.md) and [link-editor.md](../screens/link-editor.md).

## Controls

Architecture, the same idea on all devices:

- One native text view holds the entry's body: `JournalTextView` (`NativeTextView.swift`), an `NSTextView` subclass on the Mac and a `UITextView` subclass on iPhone and iPad. Both use TextKit 1 with `ListLayoutManager` (`ListLayout.swift`), which draws bullets and numbers with the text and suppresses the empty line after a final item. TextKit 2 is not used.
- SwiftUI hosts it with `NativeEditor` (`NSViewRepresentable` returning `EntryScrollView` on the Mac; `UIViewRepresentable` returning `JournalWritingView` on iPhone and iPad). Its `Coordinator` is the text view's delegate and the owner of every rule below. The text view's accessibility label is Entry text.
- The model is a `JournalDocument` of `DocumentBlock`s (JournalCore) plus the entry's Markdown. The text view shows the document as an attributed string (`RichText.render`) in which each paragraph carries its block (`journalKind`, `journalBlockID`, list number, nesting). After each edit `EditorReading` reads back only the paragraphs that changed (`RichText.document`), and `acceptEdit` puts the result in the binding, which `AppModel.updateDraft` saves ([save-entry.md](save-entry.md)). Unchanged blocks keep their stored Markdown bytes (`MarkdownDocument.applyingRichEdit`, rules M-1 to M-16).
- Markers are never characters: bullets, numbers, quote bars, rule lines and code backgrounds are drawn (`ListLayoutManager`, `BlockDecorations`); a rule has one hidden character that the caret skips (`HiddenMarkers`). Checkboxes (`InlineTasks`), tables (`InlineTables`) and pictures (text attachments) are views or cells placed over or in the text.
- Whether the entry shows Markdown source is the coordinator's flag `showsSource`, never inferred from the text. In source view the same text view holds monospaced Markdown and the structural keys keep their usual meaning (View Source is on [source-view.md](source-view.md)).
- Read-only: `view.isEditable = parent.editable`; `AppModel.canEdit` decides ([save-entry.md](save-entry.md)).
- Commands reach the coordinator as `EditorCommand` through `EditorActions.perform` and `handler`: from the Format menu (`AppCommands.swift`), the Formatting popover or panel, hardware keys, and the toolbar. A table cell with focus gets the command first (`InlineTableGrid.formatCell`).

Rule groups and where they live (spec ids):

| Rules | Where | Notes |
| --- | --- | --- |
| M (Markdown storage) | JournalCore `MarkdownDocument`, `MarkdownReader`, `MarkdownWriter`; `EditorReading`; `RichText.document` | Shared by all devices; also used by sync and export. M-12 sends unreadable Markdown to source view only (`requiresMarkdownSource`) |
| T (title) | iPhone, iPad: `TitleTextView`, a `UITextView` in the header hosted by `JournalWritingView`; Mac: `TitleTextField`, an `NSTextField` above the editor's scroll view (`EntryTitleEditor.swift`) | See Differences. Both wrap to several lines; `InitialTitleFocus` selects the whole title of a new entry |
| N, B (Return, Backspace) | `ListEditing.swift` (`RichText.newlineAction`, `itemLines`, `leavingItem`, `itemAbove`, `joining`), `HiddenMarkers.swift` (`ItemFormattingRemoval`), dispatched by `MarkdownShortcutEditing.markdownShortcutShouldChange` and `applyItemEdit` | The rules are shared. Return arrives through `doCommandBy` (`insertNewline`) on the Mac and as a `"\n"` change in `shouldChangeTextIn` on iPhone and iPad; Backspace at the start of the text through `doCommandBy` (`deleteBackward`) or the `deleteBackward` override respectively |
| E (end of entry) | `ListMarkers.hasOwnEnd`, `ListLayoutManager.setExtraLineFragmentRect`, `HiddenMarkers.caret`; E-5 `JournalTextView.tapBelowText` (iPhone, iPad only) | UIKit takes a tap below the text as a tap on the last word, so the view has its own recogniser that continues at the end |
| I (indent) | `ListIndentation.swift`, `StructuredKeyboard.swift`, `performStructuralKey` | Mac: `doCommandBy` `insertTab` and `insertBacktab`; a Tab that cannot move the item beeps (`NSSound.beep`). iPhone, iPad: `UIKeyCommand` for Tab and Shift-Tab, registered only while `StructuredKeyboard.edit` offers an edit and not in source view, so a Tab where nothing applies is the system's tab. Both announce `editor.announce.level` |
| C, G (checklists, list layout) | `InlineTasks.swift`, `ListLayout.swift`, `ListAccessibility.swift` | Checkbox: `NSButton` (Mac) or `ChecklistBox` (iPhone, iPad, with a touch height of at least 44 points), only for items in view and just beyond, and reused. A click toggles through `performStructuralKey(.toggleTask)` with the selection restored, so the caret stays. VoiceOver learns the item kind from text attributes: Mac `accessibilityListItemPrefix` and `accessibilityListItemLevel`, iPhone and iPad `accessibilityTextCustom`; quotes use a custom attribute on both |
| F, P (inline formatting, paragraph styles) | `NativeEditor.Coordinator.perform`, `RichText.toggling`, `RichTextRuns.swift`, `MarkdownEditing`, `FormattingState` | Bold, Italic, Underline: Mac `RichText.toggling` per run (each run keeps its size and traits); iPhone and iPad the system's `toggleBoldface`, `toggleItalics`, `toggleUnderline`. Strikethrough and Inline Code use `MarkdownEditing` on both. `allowsEditingTextAttributes` is on for iPhone and iPad and `WritingAccessory.hideSystemFormatting` removes the system's own B, I, U buttons so only the entry's Formatting shows |
| K (Markdown as you type) | [markdown-as-you-type.md](markdown-as-you-type.md) | Shared |
| BI (inserted blocks) | `MarkdownEditing.insertFormatted`, `exitCodeBlock`, `StructuredKeyboard.code` | Down Arrow at the end of a code block: `doCommandBy` `moveDown` (Mac), `UIKeyCommand` (iPhone, iPad) |
| TB (tables) | [edit-table.md](edit-table.md) | Shared model, two grid views |
| L (links) | `LinkEditing.swift`, `LinkEditorView.swift` (the Add Link sheet), `LinkMenuMac.swift` | ⌘K: Format ▸ Insert ▸ Add Link… or Edit Link… (Mac, iPad menu bar) and a `UIKeyCommand` on iPhone and iPad. Right-click on a link adds Edit Link… and Remove Link on the Mac and removes the system's own link items. Only `http`, `https` and `mailto` are live links (`journalInertLink` marks the rest) |
| S (source view) | [source-view.md](source-view.md); `MarkdownEditing.edit(.source)`, `SourceFormatting.swift`, `MarkdownSelection.swift`, `ModeSwitchViewport.swift` | Shared. The toggle is a toolbar button and View menu item on the Mac and a bottom-bar button on iPhone and iPad |
| SP (spelling, substitutions) | `NativeEditor.Coordinator.applySubstitutions` | Mac: `TextChecking` saves the person's Edit ▸ Substitutions and Spelling choices and turns them off in code and source, then restores them. iPhone, iPad: sets `smartDashesType`, `smartQuotesType`, `autocorrectionType`, `spellCheckingType` and `autocapitalizationType` (`.sentences` in prose, `.none` in code) |
| PA (paste, drop, copy) | `NativeTextView.swift` (`copy`, `cut`, `paste`, `writeSelection`, `readSelection`), `PastedRichText.swift`, `PastedTextInsertion.swift`, `InsertedText.swift`, `PastedImages.swift` | Own pasteboard type `org.myjournal.markdown`. Mac only: drops (`performDragOperation`, `characterIndexForInsertion`), drag mask (`draggingSession`), reading tables from rich text (`NSTextTableBlock`). iPhone and iPad: `paste` and `pasteAndMatchStyle` overrides; the source has no custom drop handling |
| IM (images in text) | [insert-image.md](insert-image.md), [image-actions.md](image-actions.md), `ImagePresentation.swift`, `ImageRefresh.swift`, `ImageThumbnails.swift` | Shared; placeholders are drawn images |
| U (undo) | `DocumentUndo.swift` (`registerSnapshot`, `restore`), `NativeEditor.Coordinator.replace`, `limitUndo`; Mac `undoStarting`, `undoCompleted` | One undo manager per text view; the entry's own changes register a snapshot of text, document, view mode, selection and typing attributes. `limitUndo` sets 100 levels. A change from elsewhere or a new entry clears it (`removeAllActions`). On the Mac the text view's undo manager is the window's, shared with Pin Entry and journal moves, so Edit ▸ Undo names them too (`undoCompleted` ignores their steps); iPhone and iPad use the text view's own |
| X (changes from elsewhere) | `ExternalEdits.swift`, `NativeEditor.Coordinator.update`, `compositionEnded` | Shared; `pendingExternal` waits while an input method composes (`hasMarkedText` or `markedTextRange`) |
| V (viewing while writing) | Mac: `EntryScrollView.typingRoom` (two lines, at most a quarter of the height) and `placeFindBar` (`TypingRoom.swift`). iPhone, iPad: `SelectionReveal.swift` (`updateWritingInset`, `revealCaretAfterEdit`, `revealCaretAfterImage`) | See Layout |

## Layout

- Column: the detail column is at most 760 points wide with 24 points of margin on each side (`RootView.editorMargin`) on all devices; the text view fills it. Insets (`EntryTextInset`): the body's container inset is 4 points on the Mac and 0 on iPhone and iPad, plus 5 points of line fragment padding on both, and the title is padded by the same amount so its first letter lines up with the body's (T-4).
- Mac: the title is an `NSTextField` above the `EntryScrollView`, so it stays in place while the body scrolls. The scroll view keeps room below the line being typed (`typingRoomLines` of 2, never more than a quarter of the height) through its bottom content inset. The find bar takes its own room above the text.
- iPhone and iPad: the title and the notices (save failure, recovery, conflict header) are one SwiftUI header hosted inside the text view (`JournalWritingView.layoutHeader` sets the container's top inset to the header's height plus 8), so they scroll with the text. The bottom inset is the room the keyboard and the writing controls cover (`updateWritingInset`: the controls' capsule frame minus the safe area, 12 points of margin, leaving at least 88 points of text). Rotation, split view changes and keyboard changes re-measure it (`layoutChanged`, `keyboardDidChangeFrameNotification`). Interrupted writing continues in a replacement editor within a second (`continueInterruptedWriting`).
- Text size: Mac `model.textSize` (View ▸ Zoom In, Zoom Out, default 16); iPhone and iPad the Dynamic Type size scaled by the same zoom (`RootView.editorSize`). Nesting depth, column width of lists (1.5 times the size, rounded) and table column minimum (7 times) follow the size.
- Content width for pictures and tables is the text view's width minus 20 points.

## Commands and shortcuts

Placement and shortcuts are as in [commands.md](../commands.md) (Editor section). The text view adds the keys below; the table lists each command the rules use. A hardware keyboard on iPad reaches the text view's own key commands (`JournalTextView.keyCommands`, not while an input method composes) in addition to the menu bar.

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `format-bold` | Format menu; Formatting; text key command on iPad | ⌘B | Entry editable and text or a cell focused |
| `format-italic` | as above | ⌘I | as above |
| `format-underline` | as above | ⌘U | as above |
| `format-strikethrough` | as above | ⇧⌘X | as above |
| `format-inline-code` | Format menu; Formatting | ⌥⌘C (menu only on iPad) | as above, not in a code block |
| `format-paragraph` | as above | ⌥⌘0 | as above; not in a table cell or code block |
| `format-heading-1` | as above (headings 1 to 6) | ⌥⌘1 to ⌥⌘6 | as above |
| `format-bulleted-list` | Format menu; Formatting | ⇧⌘7 | as above |
| `format-numbered-list` | as above | ⇧⌘9 | as above |
| `format-checklist` | as above | ⇧⌘L | as above |
| `format-mark-checked` | Format menu; Formatting | ⇧⌘U; ⇧⌘Return on iPhone and iPad text | The caret is in a checklist item (`caretTaskChecked` not nil) |
| `format-block-quote` | as above | ⌘' | as above |
| `format-increase-indent` | Format menu; Formatting; Tab | ⌘] ; Tab | `caretIndentation.increase` |
| `format-decrease-indent` | as above; Shift-Tab | ⌘[ ; Shift-Tab | `caretIndentation.decrease` |
| `insert-code-block` | Format ▸ Insert; Formatting | none; or type three backticks and Return | Entry editable |
| `insert-table` | as above | none | as above |
| `insert-horizontal-rule` | as above | none; or type `---` and Return | as above |
| `insert-link` | Format ▸ Insert ▸ Add Link… or Edit Link…, with Remove Link | ⌘K | Entry editable; Remove Link only on a link |
| `insert-image` | [insert-image.md](insert-image.md) | none | Entry editable |
| `exit-code-block` | Formatting (iPhone, iPad); Down Arrow | Down Arrow at the end of the last line | In a code block |
| `toggle-checkbox` | Click or tap a checkbox | none | Entry editable |
| `view-source` | Mac toolbar and View menu; iPhone, iPad bottom bar and keyboard accessory | ⌥⌘U | Entry editable; not available for an entry that needs source |
| `undo` | Edit menu; keyboard bar on iPad; shake on iPhone and iPad | ⌘Z | The entry or a cell has focus |
| `redo` | Edit menu | ⇧⌘Z | as above |
| `paste-and-match-style` | Edit menu | ⌥⇧⌘V | Entry editable |
| `find` | Mac find bar above the text; iPhone, iPad find navigator (`isFindInteractionEnabled`) | ⌘F | An entry is open |
| `toggle-format-as-you-type` | Settings | none | [markdown-as-you-type.md](markdown-as-you-type.md) |

Keys with no command id: Return, Backspace, Tab and Shift-Tab, Down Arrow, Space and Escape. Escape closes the Formatting popover or panel while the text keeps focus unless an input method is composing (`cancelOperation` on the Mac, `formattingEscapeCommand` on iPhone and iPad).

## Copy differences

- The Mac Format menu and the iPhone and iPad Formatting panel use the same labels; the source writes them as literals. Undo step names (Typing, Bulleted list, Increase Indent, Delete Image, Cut, View Source, Edit Link, Remove Link, Horizontal Rule, Code Block) are literal strings in the editor; only some have keys (`editor.undo.*`; see [open-questions.md](../../../open-questions.md), B16).
- Announcements are literals that equal the `editor.announce.*` keys, plus "Link removed." (not in the copy file).
- Otherwise none.

## Accessibility

- Body label Entry text and title label Title on all devices. A new entry focuses the title and selects its text.
- List and quote kinds are text attributes, not characters, so VoiceOver never reads a marker that is not in the text (G-6); numbered items carry their shown number (`ListAccessibility.renumber`).
- Checkboxes: each box is an accessibility element labelled with its item's text, or `editor.list.emptyChecklistItem` when empty. On iPhone and iPad (`ChecklistBox`) the value is `editor.list.checked` or `editor.list.unchecked`, and `JournalWritingView.checkboxElements` lists the boxes after the text. On the Mac they are `NSButton`s inside the text view whose label is set the same way; no value is set in the source. The text itself carries `editor.list.checkboxChecked` or `editor.list.checkboxUnchecked` as accessibility text attributes (`ListAccessibility`).
- Announcements (`JournalAccessibility.announce` or `NSAccessibility`): Markdown conversions, Increase and Decrease Indent (Level n), removal of item formatting (B-4), Copied, Image added, Image deleted, mode switches (`editor.announce.source`, `editor.announce.preview`), Link removed.
- Tables, pictures and checkboxes on iPhone and iPad are listed by `JournalWritingView.updateAccessibility` after the text view, in that order, then the pictures ([edit-table.md](edit-table.md), [image-actions.md](image-actions.md)).
- Reduce Motion: caret reveals on iPhone and iPad animate only when it is off (`revealCaretAfterEdit`). Dynamic Type scales the text and the touch targets of checkboxes (44 points at least, 1.3 times the text size beyond that).
- Spelling and corrections follow the person's system settings in prose and are off in code and source (SP-1, SP-2).
- Input methods: every rule that rewrites text waits while marked text exists, and a pending change from elsewhere waits for the composition to end (X-2).
- Full Keyboard Access and Voice Control: standard text view behaviour; not otherwise verified.

## Differences between iPhone, iPad and Mac

- Title: a `UITextView` in the scrolling header on iPhone and iPad; an `NSTextField` outside the scroll view on the Mac. On iPhone and iPad Return and a hardware Tab move to the body (`submit`, T-1); on the Mac Return does (the field's action) and Tab is the system's key view traversal, not app code (where focus goes was not verified). The source does not state why the title is hosted differently.
- Return, Backspace and Tab are routed differently because AppKit sends editing commands (`doCommandBy`) and UIKit sends changes and key commands. The rules are shared code.
- A Tab in a list item that cannot move it beeps on the Mac only (`NSSound.beep`, as AppKit answers a command that cannot apply). On iPhone and iPad the Tab key command is registered while the selection is in a list item or code, does nothing there when the item cannot move, and is not registered elsewhere, so in a paragraph the system types a tab.
- Bold, Italic and Underline: custom per-run code on the Mac, the system toggles on iPhone and iPad. The source does not give a reason.
- Scrolling room: the Mac keeps two lines below the caret with a content inset; iPhone and iPad keep the caret above the keyboard and the writing controls with a bottom inset, because those controls cover the text.
- A tap below the text continues the entry on iPhone and iPad (`tapBelowText`), because UIKit would select the last word; the Mac has no such tap.
- Drops, drag out to other apps and table reading from pasted rich text are customised on the Mac only; the iPhone and iPad text view keeps the system's drag and drop.
- After an undo or redo the Mac reads the text back, refreshes the pictures and reveals the caret if the text changed (U-7, `undoCompleted`, which ignores steps of other undo managers); iPhone and iPad update from `textViewDidChange`.
- The Mac find bar sits above the text (`usesFindBar`, `placeFindBar`); iPhone and iPad use the system find navigator.
- Checkbox size: 44 points of touch height on iPhone and iPad; the Mac box is a regular button.

## Screenshots

None. This flow is a set of rules for the entry editor, not a screen with a state of its own. Captures of the editor are on the Apple pages for the screens it appears in; the groups that have their own page list theirs: [edit-table.md](edit-table.md), [insert-image.md](insert-image.md), [image-actions.md](image-actions.md), [markdown-as-you-type.md](markdown-as-you-type.md).

## Source files

View:

- `apps/apple/JournalApp/Editor/NativeEditor.swift`: the representable and its coordinator (delegate methods, `replace`, `perform`, rendering) for both toolkits.
- `apps/apple/JournalApp/Editor/NativeTextView.swift`: `JournalTextView` for both toolkits (key commands, copy, cut, paste, drag).
- `apps/apple/JournalApp/Editor/JournalWritingView.swift`: the iPhone and iPad container with the header, placeholder and accessibility order.
- `apps/apple/JournalApp/Editor/EntryTitleEditor.swift`: the two title editors.
- `apps/apple/JournalApp/Editor/InlineTasks.swift`, `InlineTables.swift`, `ListLayout.swift`, `BlockDecorations.swift`: the controls and drawing over the text.
- `apps/apple/JournalApp/AppCommands.swift`: the Format, Edit and View menu items and their shortcuts.

Model:

- `apps/apple/JournalApp/Editor/ListEditing.swift`, `ListIndentation.swift`, `StructuredKeyboard.swift`, `HiddenMarkers.swift`: Return, Backspace, indent and joins.
- `apps/apple/JournalApp/Editor/MarkdownEditing.swift`, `SourceFormatting.swift`, `MarkdownSelection.swift`, `ModeSwitchViewport.swift`: formatting commands, insertions and the preview and source modes.
- `apps/apple/JournalApp/Editor/MarkdownShortcutEditing.swift`: the should-change dispatcher that the item rules and shortcuts pass through.
- `apps/apple/JournalApp/Editor/PastedRichText.swift`, `PastedTextInsertion.swift`, `InsertedText.swift`: paste and inserted text.
- `apps/apple/JournalApp/Editor/DocumentUndo.swift`, `ExternalEdits.swift`, `EditorReading.swift`: undo, changes from elsewhere, reading edits.
- `apps/apple/JournalApp/Editor/SelectionReveal.swift`, `TypingRoom.swift`: viewing while writing.

Core:

- `apps/apple/Packages/JournalCore/Sources/JournalCore/MarkdownDocument.swift`, `MarkdownReader.swift`, `MarkdownWriter.swift`, `DocumentTable.swift`: Markdown storage, reading, writing and table structure (M, TB).

Design records: `docs/design/list-markers-2026-10-03.md`, `list-indentation-2026-10-04.md`, `checklists-2026-10-03.md`, `pasted-text.md`, `menus-and-popovers.md`. Tests are cited per rule in the spec page, under `apps/apple/JournalTests/` and `apps/apple/Packages/JournalCore/Tests/JournalCoreTests/`.

## Open questions

See [open-questions.md](../../../open-questions.md). This page is a map of the code, written from the editor's source without checking every rule; it is a draft until each rule group has been read against it.

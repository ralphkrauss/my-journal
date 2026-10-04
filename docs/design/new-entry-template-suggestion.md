# New Entry with a template suggestion

30 September 2026. Scope: one New Entry button on every platform, and an optional template suggestion inside a fresh entry. This replaces the Templates… toolbar button. It builds on option D of [new-entry-button-options.md](new-entry-button-options.md), which the owner chose after trying the prototypes.

## Owner decision

The owner chose D on iPhone, iPad and Mac. In their words: on iPhone the long-press menu "is limited in number of entries and we lose the convenient search. The current iphone panel is much more convenient. I like option d actually if we can combine that button with the convenient panel that we already have. And for consistency I would also pick option D on the mac." The suggestion must "show and hide on the right moment so that it doesn't bother you if you're freely writing", and "the muted font style is perfect".

This supersedes the recorded choice to keep Templates… beside New Entry: [feedback-stabilization-2026-09-23](feedback-stabilization-2026-09-23.md) §3, [mac-window-appkit](mac-window-appkit.md) §3, and [notes-alignment-revision](notes-alignment-revision.md) (the "template icon" in the iOS bottom bar).

## 1. Toolbar and menus

- **Mac toolbar:** the editor section starts with New Entry only (`square.and.pencil`, label and tooltip "New Entry"). The Templates… item and its popover are removed.
- **iPhone and iPad:** the bottom bar shows New Entry only, next to search, in the journal list and the entry list. This is Notes' single compose button.
- **Menus:** unchanged. File ▸ New Entry ⌘N, New Blank Entry ⇧⌘N, New Entry from Template… (no shortcut; adding one would need an owner decision). On iPad, New Entry from Template… is in the ⌘ overlay with a hardware keyboard.
- **New Entry** still applies the journal's Default Template when it has one.

## 2. The suggestion

A borderless button directly below the title, in the leading column of the header:

```
Title                              ← title placeholder, focused
📄 Use a Template…                  ← muted, only in a fresh untouched entry
Start writing…                     ← body placeholder
```

- **Style:** the prototype's style, which the owner approved. It uses the body font at the `.callout` text style, placeholder color (`.secondary`), and the `doc.on.doc` symbol at the same size. It has no background or border and never takes the accent color. On the Mac a borderless button has no hover state, only a pressed state. On iPad it uses the automatic pointer hover effect.
- **Copy:**
  - "Use a Template…" when the entry is blank.
  - "Use Another Template…" when the entry holds an unchanged template (from the Default Template, or from a template chosen here or in the File menu).
- **Action:** it opens the existing template chooser, `TemplateChooserView`. Its content, search, arrow keys, Return, Escape and error copy stay the same. There is no menu.
  - **Mac:** an `NSPopover` anchored to the suggestion (preferred edge: below), shown and closed without animation. This is the same behavior as the former Templates… popover. It is not a SwiftUI `.popover`, which animates. The search field takes focus.
  - **iPad, regular width:** a popover anchored to the suggestion, presented without animation.
  - **iPhone, and iPad in compact width:** the existing "Choose a Template" sheet with `.medium`/`.large` detents and Cancel, presented without animation.
- **After a choice, the same entry is filled in place.** Same entry ID, same list row, no navigation back and forward, no second entry. The body shows the template's text. The list row updates in place and the entry stays selected.
  - Focus goes to the title, as for any new entry. The body's selection is set ready at the template's first empty answer paragraph ([template-initial-insertion](template-initial-insertion.md)), so Return or Next from the title lands there.
  - On iPhone, the keyboard comes back for the title.
  - The entry still counts as untouched: leaving it unchanged discards it, as with New Entry. The suggestion then reads "Use Another Template…".
- **Cancel:** Escape, Cancel or a click outside closes the chooser, and nothing changes. Focus follows [menus-and-popovers](menus-and-popovers.md) D1:
  - opened with the mouse or a tap: focus stays in the title;
  - opened with the keyboard, Full Keyboard Access or VoiceOver: focus returns to the suggestion, and VoiceOver is told.
- **Windows.** Each window presents its own chooser from local state, not the shared `templateChooserPresented` flag that File ▸ New Entry from Template… uses. Several windows share one `AppModel`, and the chooser opens only in the window that was clicked.
- **iPad size changes.** Popover or sheet is decided when the chooser opens. If the size class changes while it's open, it closes without applying anything.
- **Filling is not a text edit.** Undo (⌘Z) does not remove the template. The undo stack is cleared, as for a change from elsewhere. To change the template, use "Use Another Template…". To start blank, delete the text or use New Blank Entry.
- **Safety.** A template never replaces writing. The fill happens only if the entry is still this session's untouched new entry at the moment of the choice. Otherwise the choice creates a new entry from the template, as File ▸ New Entry from Template… does today, and the existing entry is left as it is. This also covers a change that synced in while the chooser was open.
- **The File menu uses the same logic.** File ▸ New Entry from Template… fills the open entry in place when it is this session's untouched new entry, and otherwise creates a new entry. Today it deletes the untouched entry and creates a new one, which looks the same in the list but flickers on iPhone.

## 3. When it shows

It shows only when **all** of these hold:

1. The open entry is the entry created by New Entry, New Blank Entry or New Entry from Template… **in this session** (`newEntryOrigin`), and it hasn't been left since. Leaving an untouched new entry already discards it, so an empty entry opened later never shows the suggestion. That covers switching entries, going back, relaunching, and entries synced from another device.
2. Nothing has changed in it since it was created or last filled from a template. The comparison is exact, not trimmed: the title, the body's Markdown, images, and the date.
3. It hasn't been **dismissed** for this entry (see below).
4. At least one template exists outside Recently Deleted.
5. The entry is editable (`canEdit`): not locked, not in Recently Deleted or an unavailable journal, not in conflict, and not read-only while saving is blocked.

**It hides for good** at the first change of any kind. One `dismissed` flag records this. It is cleared whenever `newEntryOrigin` changes (a new entry, or a template fill):

- a keystroke in the title or body, including a space or Return;
- the first marked text of an input-method composition, or dictation. The title field (UIKit and AppKit) and `NativeEditor` report a "content will change" event for every change, including marked text, and the first one dismisses the suggestion;
- paste, drop, an image insert, or a formatting command that changes the text;
- Change Date….

Deleting the text again does not bring it back.

Focus, selection, scrolling, View Source, Editor Only and zoom do not dismiss it.

**Other states:**

| State | Behavior |
| --- | --- |
| View Source | Shown. It belongs to the entry header, not to the body text, and a fill updates the source view the same way. |
| Editor Only (Mac) | Shown. The header is part of the editor. |
| Locked | Not shown; the editor is hidden. Locking discards an untouched new entry anyway. |
| Read-only, Recently Deleted, unavailable journal, conflict | Not shown (rule 5). |
| Last template deleted while shown | Hidden. |
| Offline or sync failing | Shown. Templates are local. |
| Creating the entry fails | No entry, so nothing to show. |

## 4. Layout: nothing moves

- While shown, the suggestion occupies one line between the title and the body, like the prototype.
- When it hides, it disappears immediately with no animation. Its line (the label plus the header's 12 pt spacing) is removed only when that can't move text the person is looking at:
  - **First change in the title:** the line stays reserved (empty, hidden from accessibility and hit-testing) while the title is being written. It collapses when the title stops editing (Return, Tab, a click in the body, or anywhere else) **and the body is still empty**. The only thing that moves then is the empty body's placeholder, as focus arrives there.
  - **First change in the title, body holds template text:** it stays reserved while the entry is open, because collapsing would move the questions.
  - **First change in the body** (typing, paste, an image): it stays reserved while the entry is open.
  - Any reserved line is gone the next time the entry is opened.
- If the suggestion hides without a first change, for example after Change Date… or a change synced from elsewhere, nothing was being written, so it collapses at once.
- At accessibility text sizes the label wraps to two lines within the column. It is never truncated, and the reserved space keeps the wrapped height.
- Reduce Motion: nothing animates in any case. Increase Contrast: `.secondary` follows the system's higher-contrast color.

Alternative considered: placing the suggestion at the trailing end of the title line, where it takes no vertical space. This was rejected because on the Mac it sits far from the title, it doesn't fit beside "Title" at large text sizes on iPhone, and it changes what the owner approved.

## 5. Accessibility and keyboard

- **VoiceOver:** "Use a Template…, button" (or "Use Another Template…"), with no hint. The order is title, then suggestion, then body. After a fill, VoiceOver focus moves to the title and announces it as usual for a new entry.
- **Mac keyboard:**
  - Return in the title still moves to the body.
  - Tab follows the system's Keyboard Navigation setting. With it off, Tab goes from the title to the body. With it on, Tab stops at the suggestion (Space opens the chooser), then goes to the body. Shift-Tab reverses this. Nothing traps focus.
  - File ▸ New Entry from Template… is the keyboard-first route.
- **iPad with a keyboard:** the same, with Full Keyboard Access.
- **Dynamic Type:** follows the text style up to the largest accessibility size (see §4).
- **Spelling and text settings:** the suggestion is not text in the editor, so it never gets spell-checked, selected or exported.

## 6. Implementation

- **Pure rule, new file `Model/TemplateSuggestion.swift`:** a small pure function. Inputs: the entry, the origin, the session state (`dismissed`, whether the line is still reserved), whether templates exist, and `canEdit`. Output: `.hidden`, `.useTemplate`, `.useAnotherTemplate` or `.reserved`. `AppModel` keeps the one session state and resets it whenever `newEntryOrigin` changes.
- **Exact comparison.** "Unchanged" compares the title, the date, the body's Markdown and deletion exactly. It doesn't reuse `isUntouched` (NewEntryCleanup.swift), which trims whitespace.
- **Model, `AppModel.newEntry(template:)`:** when the open draft is this session's untouched new entry in the destination journal, it fills in place and does not discard and create:
  - `draft.document = template.document`, saved with `requiringUnchanged`;
  - `newEntryOrigin` becomes the filled entry;
  - `initialInsertion` is set for the entry;
  - title focus is requested.

  Before filling:
  - it flushes pending saves (an input-method composition is committed when the chooser takes focus, and marked text counts as a change);
  - it checks that both the live draft and the stored record are exactly unchanged since the origin;
  - it saves with `requiringUnchanged` against the stored version.

  The fill runs before, and instead of, the `discardUntouchedNewEntry()` call at the top of `newEntry`, which would delete the entry being filled. If any check fails, it keeps today's behavior. `TemplateChooserView` stays unchanged.
- **Editor, `NativeEditor`:** consumes `InitialEditorInsertion` on the render that shows the filled template for the same entry, not only on a new entry's first render.
- **View, new file `Views/TemplateSuggestion.swift`:** the button and reserved line. It is used by the Mac header in `RootView` and the iOS `EntryHeaderView`.
  - The Mac popover uses a view-anchored, non-animated `NSPopover`: `ToolbarPopover` gains an `NSView` anchor, coordinated with the owner of the popover code.
  - iOS reuses the existing sheet/popover presentation with `disablesAnimations`.
- **Removed** (the prototype switch and options B/C, plus the Templates… button):
  - `Views/NewEntryButtonPrototype.swift` (deleted);
  - `Views/EntryCreationActions.swift`: single New Entry; no templates, menu, picker, `anchored` or `includesTemplates`;
  - `Views/RootView.swift` and `Views/CompactJournalNavigation.swift`: call sites and the prototype `@AppStorage`;
  - `Views/Mac/JournalToolbarController.swift`: `.templates`, `.newEntrySplit` and `.newEntryHold`, the templates popover and presentation, `chooseTemplate`, `creationStyle`, `newEntryMenu`, `canChooseTemplate`, `newEntryJournalID`, `templateChooser`;
  - `Views/Mac/RootView+MacWindow.swift`: their wiring;
  - `Views/SettingsView.swift`: the Debug picker;
  - `Views/TemplateChooserView.swift`: `TemplateChooserPresentation`, if nothing else uses it (a minimal edit, coordinated);
  - the stored `prototype.newEntryButtonStyle` default, which is no longer read and is harmless.
- **Docs:**
  - [mac-window-appkit](mac-window-appkit.md) §3 item list and width budget;
  - [menus-and-popovers](menus-and-popovers.md) rows M2, I3 and I4 (they now describe the suggestion's chooser);
  - [new-entry-button-options](new-entry-button-options.md) status (decided: D);
  - the README index.

## 7. Tests

Only tests that protect behavior:

- **Unit (`JournalTests`), the rule:**
  - shown only for this session's new entry;
  - hidden after the first title character, including a space;
  - stays hidden after the text is deleted again;
  - "Use Another Template…" after a fill or with a Default Template;
  - hidden without templates or when not editable;
  - the reserved line and when it collapses.

  These are one table-driven test.
- **Unit, the model with a real isolated store:**
  - choosing a template for an untouched new entry fills the same entry ID (one entry, template text), and the entry stays discardable;
  - when the entry changed first (a write before the choice), a new entry is created and the written one is kept unchanged. This guards the "never overwrite writing" rule;
  - when the stored record changed first (a sync) while the draft still looks untouched, a new entry is created and the synced text is left alone.
- **One iOS UI test**, replacing the Templates… steps in `FeedbackWorkflowUITests`: New Entry, then "Use a Template…", then choose Workday Log. Then check:
  - there is still a single entry;
  - the body contains the template;
  - "Use Another Template…" is shown;
  - after typing the title, no suggestion button exists.
- **Existing tests updated:** `PreReleaseUITests` (arrow keys and search field visibility) and `ScreenshotCaptureUITests` open the chooser through the suggestion instead of Templates…. The `PopoverClickGuardTests` comment mentions Templates… and is reworded.

## 8. Verification

- Mac: the toolbar and the suggestion; the popover anchored below it with no animation; fill in place; focus in the title; Tab with Keyboard Navigation on and off; the body doesn't move when typing the title.
- iPhone and iPad: the same, including the sheet and popover.
- Light and dark, the largest text size, and `.secondary` contrast in dark mode with Increase Contrast.
- A VoiceOver pass on iPhone.

## Review outcome

The independent review (30 September 2026) approved the design with required changes, and no second round is needed. The changes are applied above:

1. **Reserved line.** It no longer stays reserved for the whole session. It collapses when the title stops editing with an empty body (§4). On the Mac the header sits outside the scroll view, so a lasting gap would be the line height plus 12 pt.
2. **Fill-in-place safety.** Flush, compare both the draft and the stored record exactly, save with `requiringUnchanged`, and skip `discardUntouchedNewEntry()` for the fill (§6).
3. **Cancel focus** follows menus-and-popovers D1 (§2).
4. **Session state.** One `dismissed` flag, reset when `newEntryOrigin` changes. The per-entry set that lasted until the app quits is dropped (§3, §6).
5. **A named "content will change" hook** from the title field and `NativeEditor` (§3).
6. **Tests.** A sync-before-choice model test, a table-driven rule test, and one entry-count assertion in the UI test (§7).

Added from the review: the chooser presents per window (§2); iPad chooses popover or sheet when opening and closes on a size-class change (§2).

Optional points adopted: the Mac hover wording and the iPad hover effect (§2); a check of `.secondary` contrast in dark mode with Increase Contrast (§8); `TemplateSuggestion` as a small pure function (§6).

Not adopted: a "Blank" row at the top of the chooser. `TemplateChooserView` belongs to parallel popover work, and the row isn't a small change there. New Blank Entry (⇧⌘N) and deleting the text cover the case.


## Revision after the owner tried it (30 September 2026)

The owner said: "I don't like how 'use a template' has now introduced a bunch of wasted whitespace between the title and the body. And also I don't like how it doesn't come back when you change your mind and undo your manual text."

This revision replaces the placement (§2 layout sketch, §4) and the show/hide rules (§3). The chooser, the Mac popover, focus after Cancel, the toolbar and the Templates-screen addition are unchanged.

### Placement: inside the empty body, never its own row

- The title-to-body spacing is exactly what it was before the suggestion existed. The header has no suggestion row and no reserved line.
- The suggestion is drawn **over the empty body**, where writing would start, as an overlay that takes no layout space. Nothing moves when it appears or disappears.
  - **iPhone and iPad:** on the line below the body placeholder "Start writing…", aligned with the placeholder's leading edge. The placeholder stays as it is.
  - **Mac:** also on the body's second line, aligned with the text's leading edge, so the first line, where the caret blinks and a click places it, stays clear. Only the label's own frame is clickable.
  - **Hit area (iOS):** 44 pt tall, starting below the placeholder line, so it never covers "Start writing…" or the first line.
- **Copy:** "Use a Template…" only. It keeps the approved muted style: `.callout` text, placeholder color (`.secondary`), and the `doc.on.doc` symbol. "Use Another Template…" is dropped, because an entry holding template text has content and doesn't show the suggestion.
- It sits in empty space, so it covers nothing. A tap or click on it opens the chooser. A tap anywhere else in the body places the caret as usual.
- At the largest text sizes it wraps within the body width, still in empty space below the placeholder.

```
Title                          ← title placeholder
Start writing…                 ← body placeholder (iPhone/iPad), unchanged position
📄 Use a Template…              ← overlay in the empty body; takes no space
```

### When it shows

It shows when **all** of these hold:

1. **The entry is empty.**
   - The title is empty after trimming whitespace.
   - The body is truly empty (no characters at all, not even a space or Return) and has no images. After Return the caret moves to the second line, where the suggestion would sit.
   - A whitespace-only title counts as empty.
2. It is an entry (not a template), and editable (`canEdit`).
3. At least one editable template exists.

It hides at the first content: any character in the body (a space or Return included), a character other than whitespace in the title, a paste, dictation, marked text or an image. It **comes back** as soon as the entry is empty again, for example after deleting or undoing the text.

It isn't limited to the new entry of this session. Any empty, editable entry shows it, including an empty entry reopened later or synced from another device. That is the simplest rule, and it matches what the owner asked for: it's there whenever there is nothing to lose.

The editor's "content will change" hook, the `dismissed` flag and the reserved-line state are removed. The rule is a pure function of the entry, re-evaluated as the draft changes. On iOS the suggestion is built like the existing body placeholder in `JournalWritingView`: a subview of the text view, positioned in `layoutSubviews`. It hides on the same text-storage-length signal, so marked text and dictation hide it in the same moment as "Start writing…". It is inserted into the explicit `accessibilityElements` after the header.

### Filling in place: the rule changes, and why

Keeping "an exact match with the entry as created" would conflict with the new showing rule in two cases:
- an emptied old entry is not the session's new entry;
- a whitespace-only entry doesn't exactly match its origin.

Choosing a template there would then create a second entry instead of filling the one on screen. The fill rule becomes **"there is nothing to lose"**. It fills in place when:

- after flushing pending saves, the open draft is empty by the definition above;
- the stored record is empty by the same definition and matches the draft (the same stored version);
- the save uses `requiringUnchanged`, so a change that syncs in meanwhile is never overwritten.

Otherwise it creates a new entry, as before, and leaves the other one untouched. Whitespace-only text is the only thing the fill can replace, and the existing cleanup already discards such an entry without a trace when it's left, so this loses nothing that leaving wouldn't.

The entry keeps its date. If it was this session's new entry, it stays discardable while the template text is unchanged; an older entry that was emptied is never discarded.

### Pending owner decision

"Use Another Template…" for an entry that holds an unchanged Default Template. The owner is being asked. The rule is a single function, so this is one more case if the answer is yes.

### Review outcome (revision)

The quick independent review approved the revision with required changes, applied above:
- on the Mac, the suggestion moves to the second line and only the label is clickable;
- it shows only for a truly empty body (a whitespace-only title still counts as empty; the fill rule still treats whitespace as nothing to lose);
- on iOS it is built like the existing placeholder, and it is part of the accessibility order;
- a rule case covers a body of only newlines;
- the UI test checks positions in screenshots, not pixels.

The optional 44 pt iOS hit area below the placeholder line is adopted.

### Accessibility

- VoiceOver order: title, then "Use a Template…, button", then the body text.
- It leaves the accessibility tree while hidden.
- Keyboard access is unchanged: File ▸ New Entry from Template…, and Tab with Keyboard Navigation on the Mac.

### Tests (revised)

- **Rule:** one table-driven test.
  - Shown: empty; a whitespace-only title; an emptied older entry.
  - Hidden: a title character; body text; a body of only spaces or newlines; an image; a template; not editable; no templates.
- **Model:**
  - filling an empty new entry keeps one entry;
  - filling a whitespace-only entry fills in place;
  - typed text before the choice gives a new entry and keeps the text;
  - a synced change before the choice gives a new entry and keeps the synced text;
  - an emptied older entry fills in place and keeps its date.
- **UI (iPhone):** new entry, then check the suggestion is shown. Type a title and check it hides; delete the title and check it's back; choose a template and check the entry is filled in place. Positions are checked in screenshots, not asserted in pixels.

## Revision 3: part of the placeholder (owner's choice, 30 September 2026)

The owner found the second-line suggestion awkward and chose option 2: the link is part of the body placeholder. This replaces the placement and the "Use Another Template…" rule of the revision above. The chooser, the fill-in-place safety, the toolbar and the Templates-screen addition stay as they are. "Use Another Template…" is dropped: to switch templates, clear the entry and the link comes back. New Entry still applies a journal's Default Template.

### Copy

- With at least one editable template, the empty body shows one placeholder line: **"Start writing or use a template…"**.
  - There is no comma: "start writing" and "use a template" share one implied subject, so Apple style doesn't separate them.
  - The ellipsis belongs to the link, because it opens a chooser. It also matches today's "Start writing…".
  - "Start writing or " is plain placeholder text. **"use a template…"** is the link.
- Without templates, or when the entry can't be edited: **"Start writing…"**, as today, with no link.
- VoiceOver label of the link: **"Use a Template"**, in title case like a button, without the ellipsis.

### Look

- Placeholder text: the existing body placeholder style (the body font and size, `tertiaryLabel` on iOS, `placeholderTextColor` on the Mac).
- Link: the same font. The colour is one step stronger than the placeholder (`secondaryLabel` / `secondaryLabelColor`), with a solid thin underline in the same colour, so it reads as a quiet link rather than as more placeholder text. It never uses the accent colour. A dotted underline was considered and dropped because it looks fussy at small sizes.
  - Pressed (iOS) or clicked (Mac): the text turns `label` colour while pressed. There is no other hover effect on the Mac. On iPad with a pointer, it uses the automatic hover highlight.
- **Mac:** the body gets the same placeholder line. The original design (screens.md) gave both platforms "Start writing…", but the Mac body never showed one. It is drawn at the first line's position with the text container's inset and line padding, exactly where the first typed character goes.
- There is no extra line and no layout space. The placeholder occupies the empty first line, as today.

### When it shows

- It shows and hides **exactly with the body placeholder**: the body has no characters and no images. The first character hides both; emptying the body (deleting or undoing) brings both back.
- **Title:** the title placeholder "Title" is independent. The link stays while a title is typed, because the body is still empty. Choosing a template then fills the body and keeps the title.
- The link also needs an editable entry (`canEdit`), a live journal and at least one editable template. Otherwise the placeholder is "Start writing…".
- It isn't limited to new entries: any empty body shows it.

### Filling (clarified)

- A choice fills the **body** in place when the body has nothing to lose (whitespace only, no images), both in the open draft and in the stored record, with the same stored version, saved with `requiringUnchanged`.
- The title is kept as typed. Otherwise the template goes to a new entry, as before.
- Focus afterwards: the title if it's empty. With a typed title, focus doesn't move; the body's selection is already set at the template's first answer paragraph, so Return in the title or a tap in the body continues there.
- **Undo:** the fill clears only the body's undo history, as any change from elsewhere does. Typing in the title, and its undo, are kept.

### Hit target

- **iOS and iPad:** only the link's own text is interactive, extended to a 44 pt tall target centred on the placeholder line. It is never wider than the link text. A tap on "Start writing or " (or anywhere else in the body) just places the caret, as today. The extra height reaches only into empty space (the gap under the header and the empty line below).
- **Mac:** the link's text frame only. A click elsewhere on the line places the caret.

### Construction

- **Two views, never one label.** A plain, non-interactive label shows "Start writing or " (or "Start writing…" without the link). A real button shows "use a template…". The button follows the label's text on the same line; when it doesn't fit, it moves to the start of the next line.
  - iOS: the label is the existing placeholder `UILabel` in `JournalWritingView`. The button is a hosted SwiftUI view added below the header in z-order.
  - Mac: the same two views are subviews of the text view. The label ignores clicks.
- **iOS taps:** a tap on the link opens the chooser without raising the keyboard or moving the caret first. The text view doesn't begin its own gestures inside the link's target. The 44 pt target sits below the header in z-order and never reaches over the title, so it never steals a title tap.
- **Mac Tab order**, with Keyboard Navigation on: title → link → body, and back with Shift-Tab. It is set explicitly on the key-view loop by the editor while the link is shown, and restored to title → body while it's hidden (`EditorPlaceholder.swift`).
- **Mac VoiceOver:** the text view's accessibility children include the link (`JournalTextView.accessibilityChildren`), so VoiceOver reaches it as a button.

### Wrapping and text size

- The placeholder follows the body text size (Dynamic Type on iOS, View ▸ Zoom on the Mac).
- When "Start writing or use a template…" doesn't fit on one line, the link moves to the start of the next line. It is never truncated.
- At the largest accessibility sizes it may take two or three lines. All of them are empty space in an empty body, so nothing is covered, and they disappear with the first character.

### Accessibility

- The placeholder text itself stays out of VoiceOver, as the existing placeholder does (unified-entry-scrolling.md). The empty body is announced by its label, "Entry text", as today.
- The link is a separate button element, "Use a Template", ordered after the title and before the body: on iOS through the writing view's explicit `accessibilityElements`, on the Mac through the text view's accessibility children.
- It leaves the accessibility tree with the placeholder.

### Keyboard access

- File ▸ New Entry from Template… (Mac, and iPad with a keyboard) opens the same chooser and fills an empty body in place.
- The link is a focusable button: Tab with the Mac's Keyboard Navigation setting on, or with Full Keyboard Access on iPad. Return from the title still goes to the body.

### Appearance

- Dark mode and Increase Contrast come from the semantic colours above.
- Checked on screen in dark mode with Increase Contrast, and at the largest text size.

### Removed

- The separate suggestion line.
- The "Use Another Template…" rule, its title and its tests.
- The Default-Template replacement branch of the fill rule.

### Review outcome (revision 3)

The quick independent review approved revision 3 with required changes, applied above:
- two views (a label and a real button), with the button moving to the next line when needed;
- iOS taps: the link doesn't raise the keyboard or move the caret, and its target stays below the header;
- the Mac Tab order and VoiceOver children are set explicitly, and where is documented;
- undo: only the body's history is cleared by a fill.

The optional solid underline is adopted.

### Tests

- **Rule table:**
  - Link shown: empty body, with or without a title.
  - Link hidden: body text; only newlines; an image; no templates; not editable; a template.
- **Model:**
  - the existing fill tests;
  - with a title typed and an empty body, a choice fills the body and keeps the title.
- **UI (iPhone):** the link is shown; the first character hides it; deleting brings it back; a choice fills the entry in place. Positions are checked in screenshots.
- **Verification on screen:**
  - a tap on the link opens the chooser without raising the keyboard or moving the caret;
  - a tap on the title near the link focuses the title;
  - the Mac Tab order, if Keyboard Navigation can be turned on;
  - the largest text size, and dark mode with Increase Contrast.

## Owner decision: the template symbol instead of an ellipsis (30 September 2026)

The owner said: "I would prefer that instead of the triple dot that you use the icon for 'use a template' just like how we had it before". No new review is needed.

- The placeholder reads "Start writing or [doc.on.doc] use a template". The link is the symbol followed by "use a template", with no ellipsis. Without templates it stays "Start writing…".
- The symbol is part of the link button, in the same muted colour.
  - It is sized to the placeholder text (Dynamic Type on iOS, View ▸ Zoom on the Mac).
  - It sits on the text's baseline: inline in the text on iOS; a text attachment centred on the capitals on the Mac.
  - It is decorative: VoiceOver reads the button as "Use a Template".
- Only "use a template" is underlined.
- When the link moves to the next line, the symbol moves with it. At the largest sizes the link itself can wrap; its frame is measured at the width it gets, so it never overlaps the line above.

## Placeholder rebuilt as text (30 September 2026)

The owner found the symbol badly aligned: "the lining and positioning of that icon needs to be completely rechecked and make sure that it respects the proper line heights, with normal text size as well as with the accessibility large text." The two-view layout (a label plus a separately placed button) caused this. The placeholder is now real text:

- **One attributed string**, laid out by TextKit 1 with the body's font, paragraph style and line height (`PlaceholderText`, EditorPlaceholder.swift):
  - "Start writing or " in the placeholder colour;
  - then the link run: the `doc.on.doc` symbol as a text attachment, a non-breaking space, and "use a template" underlined, in the link colour.
  - The link run uses non-breaking spaces so it moves to the next line as a unit. It breaks between its words only when it is wider than a line on its own (at the largest sizes).
- **The symbol** is configured with the body font at the `.small` symbol scale and keeps its own baseline, so it sits on the text's baseline and centres on the capitals.
  - The medium scale reached above the font's ascender and pushed the line down.
  - The paragraph's minimum and maximum line height are the font's own, so the placeholder's lines match typed text line for line.
- **Placement:** the text view sits in the body's own text container (same inset and line padding), so its lines are exactly where typed text's would be.
- **Taps:**
  - iOS: a transparent button covers the link's glyph rectangle, padded to 44 pt, and VoiceOver reads it as "Use a Template".
  - Mac: a transparent button covers the glyph rectangle, with the same Tab order and accessibility children as before.
  - The pressed colour change is dropped, because the text is drawn by the placeholder rather than the button.
- **Measured on screen** (iPhone 17, device pixels; see template-placeholder-sizes.png, Default, xLarge, AX1, AX3 and AX5, light and dark):
  - the placeholder's baselines equal typed body text's at every size;
  - the line pitch equals the body's (103, 142 and 180 px at AX1, AX3 and AX5);
  - the symbol's centre is within 1 px of the capitals' centre, and its height is 1.32–1.36× the cap height;
  - the left edge equals the body's.
- **Known, not new:** changing Dynamic Type while an empty entry is open can leave the space under the title at the previous size's height until the entry is reopened. The header's measured height lags; it affected the old placeholder the same way. It's recorded as a follow-up.

## Owner decision: new entries are kept (30 September 2026)

The owner, after using the iPhone build: "when I use the create new entry item and then immediately go back on ios there is this weird state that the entry dissapears again. I want to keep the empty entries once you create them. We don't need any special logic for deleting them again".

- **An entry stays once it's created, even if it's left empty,** on every platform. Leaving it (going back, opening another entry, switching journals or collections, locking or quitting) keeps it in the list, like any other entry. It can be deleted like any other entry. This reverses [owner-decisions-2026-09-25.md](owner-decisions-2026-09-25.md) §5 ("Discard untouched new entries"). The cleanup (`NewEntryCleanup.swift`, `discardUntouchedNewEntry()`) and the `newEntryOrigin` it relied on are removed.
- **Filling in place doesn't change.** A template fills the open entry only when there is nothing to lose: after saving pending changes, both the draft and the stored copy have an empty body (whitespace at most, no images) at the same stored version, and the save uses `requiringUnchanged`. Otherwise the template goes to a new entry. Earlier sections that say an untouched entry is "discarded" or "stays discardable" no longer apply.
- **Merging.** An empty entry counts as something written: a library with one no longer counts as "nothing written", so connecting to a server offers to merge rather than replace it. This was already the rule (`LibraryContents` counts every entry outside Recently Deleted), and it's now the right one, because the entry would otherwise be lost silently.
- **Tests.** The cleanup test became "an empty new entry stays when left" (`DeletionFlowTests`). The merge test lists an empty entry as written (`MergeTests`). The iPhone back-navigation UI test goes straight back from a new entry and checks that its row stays (`MobileParityUITests`).

## Addition: start an entry from the Templates screen

Owner request (30 September 2026): "you can start an entry from a template, from the templates screen. That would also be convenient."

### Entry points

The action lives in the template's own actions catalog (`entryActionCatalog`), so every place that shows a template's actions offers it in the same way:

- **Template row context menu:** right-click on the Mac; touch and hold on iPhone and iPad. It is the first item, followed by a separator, then the existing Version History… and Delete Template.
- **Entry Actions "…" while a template is open:** the Mac toolbar menu and the iPhone/iPad top-bar menu. It uses the same catalog, so it gets the same item.
- **No swipe action.** Notes has no leading swipe for this, a swipe creates entries too easily by accident, and the trailing swipe stays Delete.
- **No extra toolbar button.** This keeps a single New Entry button (§1). New Entry in the toolbar keeps its meaning while Templates is shown: a new entry with the journal's Default Template.

### Which journal

> Superseded by [template-journal-choice-2026-10-03.md](template-journal-choice-2026-10-03.md) for the Templates list and File ▸ New Entry from Template… outside a journal: the person chooses the journal (New Entry In ▸). The text below records the earlier rule.

One rule, one resolver: `newEntryJournal` is the selected journal, otherwise the default journal. From All Entries it stays the default journal. The toolbar's New Entry and this item both use it, so they always agree. Creating the entry selects that journal (`selectedJournalID`), so the list and sidebar show where it went.

The item names the journal when there's a choice (see Copy), so nothing is hidden. The app never asks: New Entry doesn't ask either, and Move Entry… changes the journal afterwards.

### What happens

1. The open template's pending edits are saved first. The template is then looked up again by its ID, so the entry uses it exactly as it is now written. If the template is gone, or has changes to review, nothing is created and an alert explains why (see Copy).
2. The app leaves Templates and shows the destination journal, with the new entry open and filled from the template, the same as File ▸ New Entry from Template… today:
   - the title is focused (on iPhone, with the keyboard);
   - the body selection is set at the first empty answer paragraph;
   - an entry left untouched is discarded.
3. **iPhone:** the navigation stack becomes [journal list, new entry] without animation, as the Journals screen's compose button does. Back returns to the journal's entries, not to Templates.
4. **Mac and iPad:** the sidebar selects the journal, the list shows it, and the editor shows the entry. All Mac windows share one model, so every open window leaves Templates for that journal, as they already do for any collection change.
5. Inside the new entry, "Use Another Template…" appears as for any template-created entry (§2 and §3).

### Copy

- Menu item, with the `square.and.pencil` symbol and no ellipsis, because nothing more is asked:
  - **New Entry from Template** with one live journal, matching File ▸ New Entry from Template…;
  - **New Entry in “‹Journal›”** with more than one live journal ("Untitled Journal" for a journal without a name). Superseded: now a **New Entry In** submenu (template-journal-choice-2026-10-03.md).
- Alerts, when the template changed since the menu opened:
  - "This template is no longer available.";
  - "Review the changes to this template first."
- The chooser lists only templates this version can edit (a template in a newer format can't make an editable entry), which matches "not shown" below.

### Disabled and hidden states

| State | Item |
| --- | --- |
| Locked | Not reachable (nothing is shown). |
| No live journal (all in Recently Deleted or unavailable) | Shown, disabled. New Journal… is in the sidebar and File menu. |
| Template in Recently Deleted | Not shown. Those rows offer Restore and Delete Permanently only. |
| Template with changes to review (conflict) | Shown, disabled, until the changes are reviewed. The choice would otherwise use one of two versions without saying which. |
| Template this version can only read (unsupported format) | Not shown. The entry couldn't be edited. |
| Saving is blocked (save failure) | Disabled, as New Entry is. |

### Accessibility

- It is a standard menu item with the label "New Entry from Template".
- VoiceOver reaches it through the row's context menu (the Show Context Menu action on iOS, VO-Shift-M on the Mac) and through the Entry Actions button while a template is open.
- Keyboard: the Mac context menu key, or Entry Actions from the toolbar with Full Keyboard Access.
- After it runs, focus is in the new entry's title, as after File ▸ New Entry from Template…, and VoiceOver announces the title field.

### Tests

- **Model (isolated store):** with Templates shown after a journal was selected, creating from a template:
  - makes one entry in that journal with the template's text, including unsaved edits made to the template just before;
  - leaves Templates and opens the entry, both checked in the same test;
  - leaves the template unchanged.
- **Model:** with no journal selected, the entry goes to the default journal, and that journal becomes the selected one.
- **Catalog:** no separate test. The row menu and the Entry Actions menu are built by one function (`entryActionCatalog`), so they can't drift apart; a test would only restate that.
- **One iOS UI step** in an existing template test: touch and hold a template row, choose New Entry from Template, then check the body shows the template and Back returns to the journal's entries.

### Review outcome (addition)

The independent review approved this addition with required changes, and no further review is needed. The changes are applied above:

1. The item names the destination journal when there are several.
2. One destination resolver (`selectedJournal ?? defaultJournal`) is used by New Entry and this item, and creating the entry selects that journal.
3. The template is looked up again after saving. If it's gone or has changes to review, an alert appears and nothing is created.
4. The doc states that all Mac windows leave Templates.
5. The tests add a case with no journal selected, check "leaves Templates" and "opens the entry" together, and keep the catalog test to menu parity only.

The chooser now lists only editable templates, to match the "not shown" rule.


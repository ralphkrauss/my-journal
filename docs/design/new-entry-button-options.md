# New Entry button: folding in Templates… (experiment)

30 September 2026. Scope: how New Entry could offer templates without a second toolbar button.

Status: **decided — the owner chose D on all platforms (30 September 2026); see [new-entry-template-suggestion.md](new-entry-template-suggestion.md).** Originally a prototype for the owner to compare, not a reviewed design. Once the owner picks an option it goes through the design gate in AGENTS.md (design, independent review, implementation, inspection), and the prototype switch is removed.

## Problem

The owner: the two-icon group [New Entry, Templates…] makes the template icon compete with the main action. Fold them into one control: a click creates a new entry; an extra click starts from a template.

This revisits the earlier decision to keep Templates… visible beside New Entry ([feedback-stabilization-2026-09-23](feedback-stabilization-2026-09-23.md) §3, [mac-window-appkit](mac-window-appkit.md) §3). The owner asked for it, so the prototype changes it only behind a Debug switch.

Unchanged in every option:

- New Entry uses the journal's Default Template, if it has one (the "Default Template" submenu in the journal's actions).
- File ▸ New Entry ⌘N, New Blank Entry ⇧⌘N, New Entry from Template… (no shortcut; the recorded shortcut decisions are not changed).
- The template chooser (`TemplateChooserView`) is reused as it is: search, arrow keys and Return, no animation.

## Research

| Pattern | Where | Notes |
| --- | --- | --- |
| Pull-down button with a primary action | Apple HIG, [Pull-down buttons](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons) | Use it for "commands or items that are directly related to the button's action", e.g. an Add button that lets people specify what to add. Warns not to hide a view's primary actions in the menu. The primary action here stays one click. |
| Touch and hold reveals a menu | HIG, same page | "Safari responds to a touch and hold gesture on the Tabs button by displaying a menu of tab-related actions, like New Tab". Safari's Back button works the same way. |
| NSMenuToolbarItem with an action | [NSMenuToolbarItem](https://developer.apple.com/documentation/appkit/nsmenutoolbaritem) | With an action, a click runs it and press-and-hold shows the menu; with `showsIndicator`, the indicator becomes a separate segment that opens the menu on click. This is the Mac's native split toolbar button. |
| SwiftUI `Menu(primaryAction:)` | [Menu](https://developer.apple.com/documentation/swiftui/menu/init(content:label:primaryaction:)) | iOS: tap runs the primary action, touch and hold opens the menu. |
| Primary action + variants in Apple apps | Mail (Mac) | The Move To toolbar button moves to the predicted mailbox on click; hold shows all mailboxes ([Mojave Mail notes](https://support.ntiva.com/hc/en-us/articles/360020287552-File-Messages-Faster-in-Mail-in-Mojave)). |
| Default template setting | Pages, Keynote, Numbers | Settings ▸ For New Documents: show the template chooser, or use one template. File ▸ New… vs. New from Template Chooser. Same shape as our Default Template + New Blank Entry. |
| Journal app: hold + for templates | [Day One](https://dayoneapp.com/guides/getting-started-with-day-one/creating-entries/) | Long-press + on iOS shows templates. When a 2024 redesign removed it, users protested and it came back in 2024.13 ([forum thread](https://forums.dayoneapp.com/forums/topic/new-design-30th-may-2024-removed-quick-access-to-templates-why/)). Frequent template users want one-gesture access. |
| Templates offered inside the empty page | [Notion](https://www.notion.com/help/guides/creating-a-page), Craft | A new empty page offers templates until you start typing. Very discoverable, but it adds content-area chrome. |

Takeaways:

1. Folding variants into the create button is an established Apple pattern on both platforms: a split button on the Mac, touch and hold on iOS.
2. Touch and hold alone is hard to discover. Day One users who knew it relied on it heavily. The HIG pairs it with a visible or menu-bar route.
3. With a Default Template, "New Entry" can already mean "from template", so the menu needs **New Blank Entry** in that case (like Pages' "use template" setting plus New…).

## Options in the prototype

Menu contents (options B and C, Mac and iOS):

- **New Blank Entry** (`doc`), then a separator. Only when the journal has a Default Template.
- One item per template, by name (`doc.text`), sorted as in the Templates list. Choosing one creates the entry at once, like choosing it in the chooser. Duplicate names get the same short ID suffix as the chooser.
- More than 10 templates: a single **Choose Template…** (`doc.on.doc`) item opens the chooser with search instead.
- No templates: a disabled **No Templates** item.

### A. Current (two buttons)

Unchanged: [New Entry] [Templates…].

### B. Split Button (Mac only)

- Mac toolbar: one `NSMenuToolbarItem` with `showsIndicator`: the compose icon, and a chevron segment. Click the icon: New Entry. Click the chevron, or click and hold the icon: the template menu. Like Mail's Move To button.
- iPhone and iPad have no visible split style for toolbar buttons, so there this option behaves like C.
- Accessibility: the icon segment is "New Entry, button". The AppKit chevron segment is currently exposed without a label (seen in the accessibility tree); a final version needs a check with VoiceOver and, if needed, a label such as "Templates".
- Pros: discoverable (visible chevron), native, one click for both paths. Cons: the chevron still adds some width and visual weight, though much less than a second icon.

### C. Press and Hold

- Mac: the same toolbar item without the chevron. Click: New Entry. Click and hold: the template menu. VoiceOver: "New Entry, button", with the standard Show Menu action.
- iPhone and iPad: `Menu(primaryAction:)`. Tap: New Entry. Touch and hold: the template menu, like Safari's Tabs button. VoiceOver: double-tap creates the entry; a custom action "Choose Template" opens the chooser.
- File ▸ New Entry from Template… stays on the Mac and on iPad with a keyboard.
- Pros: the cleanest toolbar, exactly Notes' single compose button, and the Day One pattern for fast template use. Cons: hidden. People who don't know about the hold only find templates in the File menu (Mac) or not at all (iPhone).

### D. In the New Entry

- One New Entry button everywhere, with no menu.
- An untouched new entry shows a quiet borderless button below the title: **Use a Template…** (secondary color, `doc.on.doc`). When New Entry already applied the Default Template it reads **Use Another Template…**. It opens the chooser (a popover on the Mac, a sheet on iPhone). Choosing a template replaces the untouched entry with one from that template.
- It disappears as soon as you type a title or text, add an image or change the date (the same "untouched" rule that discards empty new entries), or when you open another entry.
- VoiceOver: "Use a Template…, button", right after the title field.
- Pros: the most discoverable, and it appears exactly when it is relevant. It also works on iPhone without a hidden gesture. Cons: content-area chrome in the writing view (AGENTS.md asks for "no persistent visual clutter"; this is temporary but visible on every new entry). The text jumps up by one line when it disappears. The prototype replaces the entry by creating a new one, which on iPhone shows a brief back-and-forward transition; a final version would fill the same entry in place.

## Recommendation

**C (Press and Hold) with the discoverability of B on the Mac**, i.e.:

- Mac: B, the split button. It is the native Mac answer for "primary action + related variants", visibly quieter than a second icon, and still discoverable.
- iPhone and iPad: C, a single compose button with touch and hold (the only native iOS form of B).
- Keep File ▸ New Entry from Template…. Optionally give it a shortcut, such as ⇧⌥⌘N (⌥⌘N is New Journal). That needs an owner decision, because shortcuts are recorded decisions.

D is worth trying for how it feels, but it adds writing-view chrome and is the most work to finish well. It could be added later for people with templates but no Default Template, if the hidden gesture proves too hidden on iPhone.

## Trying the options

Debug builds only (a Release build always uses A):

- **Mac:** My Journal ▸ Settings… ▸ General ▸ Prototype ▸ **New Entry Button**: Current, Split Button, Press and Hold, In the New Entry. The toolbar changes at once.
- **iPhone and iPad:** Settings (gear) ▸ Writing ▸ Prototype ▸ **New Entry Button**: Current, Press and Hold, In the New Entry.
- The choice is stored in `UserDefaults` (`prototype.newEntryButtonStyle`).

## Implementation notes (prototype)

- `Views/NewEntryButtonPrototype.swift`: the style enum and switch, the shared menu, and the in-entry suggestion. Delete this file when the experiment ends.
- `Views/EntryCreationActions.swift` (iOS bars), `Views/Mac/JournalToolbarController.swift` (two extra toolbar identifiers and their menu), `Views/Mac/RootView+MacWindow.swift` and `Views/RootView.swift` (wiring), `Views/EntryHeaderView.swift` (iOS header), `Views/SettingsView.swift` (Debug picker).
- Verified on screen: Mac (all four, the in-entry chooser, typing removes the suggestion) and iPhone 17 simulator (A, C with the menu open and a template chosen, D with a template chosen). Not verified: the Mac menus opened by the chevron or by holding (they need the window in front), iPad, VoiceOver, largest text size.

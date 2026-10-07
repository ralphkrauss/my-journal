---
id: markdown-as-you-type
title: Markdown as you type (Windows)
spec: flows/markdown-as-you-type.md
features: [markdown-as-you-type]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/input/keyboard-accelerators
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.richeditbox.textcompositionstarted
---

# Markdown as you type (Windows)

A marker typed at the start of a line becomes the formatting it stands for, and is easy to take back. Steps and copy keys are the spec's [markdown-as-you-type](../../../flows/markdown-as-you-type.md); the precise rules are K-1 to K-6 and N-12 of [editing-rules](editing-rules.md), whose Windows ratings apply here.

## Controls

There is no control of its own. The setting is a `ToggleSwitch` in the General page of Settings (`settings.general.formatAsYouType`; [screens/settings-general](../../../screens/settings-general.md)), on by default. The conversion runs in the editing control's key handler ([entry-editor](../screens/entry-editor.md)).

**Applies** while typing in the body, in preview (not source view), with the setting on, in a plain paragraph (not a heading, item, quote, code block or table cell), never while an input method composes and never on pasted text.

## Steps on Windows

1. The person types a marker at the start of a plain paragraph, then Space: `- `, `* `, `+ `, `n. ` or `n) ` (1 to 9 digits), `[ ] `, `[] `, `[x] `, `[X] `, `> `, or `# ` to `###### `. Numbers such as `1.5 ` and a word such as `Note: ` do nothing.
2. **The space is typed as one undo step, then the line converts as a second step.** The Space key is handled in `PreviewKeyDown`: the app inserts the space itself and closes an undo group, then converts the line in a second group. The marker's characters are removed, text after the caret becomes the new block's text, the caret is at its start and typing continues in the new style. Because this is synchronous in the key handler, a burst of keys ("- Milk", Enter, "Eggs" at any speed) keeps every letter in order and in the right item.
3. **Narrator is told the new style** (`editor.announce.bulletedList`, `editor.announce.numberedList`, `editor.announce.checklist`, `editor.announce.blockQuote`, `editor.announce.heading`) as a notification event, `ImportantMostRecent` ([11](../platform.md#11-progress-and-announcements)).
4. **Taking it back.** Backspace straight after the conversion gives back exactly what was typed ("- ") as a plain paragraph, as one undo step named `editor.undo.typing`, with the caret after it; that line is not converted again while typing continues. Ctrl+Z instead gives back the typed marker and space first (named after the style), then removes the space (named `editor.undo.typing`).
5. **Blocks on Enter.** Enter at the end of a plain line that is exactly `---`, `***` or `___` makes a horizontal rule (announced `editor.announce.horizontalRule`, undo step `editor.undo.horizontalRule`); a line that is exactly three backticks, optionally followed by a language name (letters, digits and `+ - _ # .`), makes an empty code block with the caret inside (`editor.announce.codeBlock`, `editor.undo.codeBlock`). Backticks followed by other text do nothing.

### Text that arrives without key presses

Voice typing (Win+H), handwriting, the touch keyboard's suggestions and the emoji panel insert text without a Space key press. The spec treats dictation like typing, so the text-changed handler runs the same check when a single space is inserted after a marker at the start of a plain paragraph and no composition is open. Longer insertions are not converted (they are pasted-like text). To confirm in D40.

## Layout at each window width

Not applicable. The flow has no layout.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `toggle-format-as-you-type` | `ToggleSwitch` in Settings ▸ General | none | Always |

Keys: Space (converts), Enter (rules and code blocks), Backspace (takes back), Ctrl+Z (undoes in two steps). Esc does nothing here.

## Copy differences

The footer of the setting, `settings.general.formatAsYouType.footer`, names the Delete key that undoes a conversion: Windows says "Backspace" (platform.md, 12.3). The announcements and undo names are sentence case ("Bulleted list", "Block quote"). No other differences.

## Accessibility

- Every conversion is announced, because it is not otherwise visible to a screen reader. Announcements are not repeated for the same style twice in a row within a second.
- Taking a conversion back is announced as the paragraph it returns to (`editor.announce.paragraph`).
- The setting's switch is a standard `ToggleSwitch` with its footer as description.

## Different by design

- **Windows has no per-platform difference in behaviour.** The mechanism differs: Apple converts in the text view's change hook; Windows handles the Space key and Enter before the control and checks text-changed events for input that has no keys.
- **Key names:** Backspace, Enter, Space.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D30 (editor control), D40 (text that arrives without key presses).

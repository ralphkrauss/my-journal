# Native device orientation

## Problem and intended behavior

The iOS target supports iPhone and iPad but declares no supported orientations. Physical-device archive validation warns that all orientations must be supported unless the app requires full screen. Keep native adaptive layout and iPad multitasking; do not require full screen to silence validation.

Declare portrait and both landscape orientations for iPhone, and all four orientations for iPad (including upside-down portrait), using the standard Info.plist keys. Let SwiftUI navigation and native sheets adapt without introducing orientation locks or custom layouts. No new controls or copy. Existing empty, error, locked and editing states retain their behavior.

Rotation must preserve the selected journal, entry, unsaved writing and editor focus where the OS permits. Honor Dynamic Type and keyboard-safe areas. Verify a real simulator rotation while editing and returning to portrait, with persisted content after relaunch. Inspect both orientations, and validate a device archive without the orientation warning. This bounded check does not establish every iPad window size or physical-device behavior.

## Independent review

Approved before configuration changes; see [independent review](device-orientations-review.md). Actual rotation evidence remains pending.

## Largest-text short-height correction proposal

Actual largest-text landscape capture shows the title partly clipped while the body line/caret remain visible above the keyboard. EntryHeaderView spends 28 points of its half-height viewport on top spacing, plus 12 below. When available editor height is below 240 points, remove these vertical decorative insets (retain horizontal 28); otherwise preserve existing spacing. Keep the header scrollable, its half-height cap, native title font, failure/recovery/conflict notices and focus ownership. Do not scale system fonts or introduce hidden controls. The threshold applies to available content height, including native keyboard avoidance, rather than detecting orientation/device.

Inspect complete current title line and body/caret at largest text with keyboard, and returned portrait. Long titles still scroll naturally in the header; this proposal does not promise simultaneous visibility of arbitrary title lines. If removing spacing cannot fit one complete title line, revisit layout before claiming acceptance.

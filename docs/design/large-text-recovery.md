# Large-text trash layout correction

Actual simulator recovery E2E passes at accessibility-extra-extra-extra-large in dark mode after teaching the test to scroll native menus/forms. Visual inspection of artifacts/journal-large-dark-scroll-previews/7F2F9003-74BD-4AB4-BDFA-674F0AE22534.png nevertheless shows the separate safe-area retention note overlapping the list's Entries/month text. This is an app layout defect, not a test failure to suppress.

Proposed correction: remove the bottom safeAreaInset for the retention note. Render the same sentence once as the final secondary-text row in Recently Deleted's native List, using a clear row background. It scrolls with the content and takes its measured height rather than covering rows. Keep the search field in its native location. No font shrinking or Dynamic Type cap; retain system dark surfaces. Empty collection state continues to identify No Deleted Items; show the note only with results so it does not collide with the empty-state overlay.

The journal selector's native label may truncate as other navigation labels do; its accessibility name remains the full collection/journal name. Do not add a huge unbounded fixed header to solve truncation. Confirmations already scroll and the actual run reached Delete/Restore; their full text need not fit on one screen. Capture scrolled action states as well as top-of-sheet states to document reachability.

Review this bounded change before implementation. Then rerun the single actual large-text/dark recovery E2E, inspect trash at top and after scrolling to its note/entry, and verify original simulator appearance/text settings are restored after testing.

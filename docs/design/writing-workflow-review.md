# Everyday writing workflow review

## Initial screenshot and source review — 2026-09-21

**A material template-writing correction is needed; no search redesign is warranted by this evidence.** Independently inspected the three supplied captures in `artifacts/writing-workflow-before`, WritingWorkflowUITests, EntryHeaderView's title submission, NativeEditor's focus/render behavior, RichText rendering/newline handling and AppModel.newEntry's template copy. No production edits or test reruns occurred. These screenshots are from an author-reported failed fixture run; no successful end-to-end or store-assertion outcome is credited here.

### P2 — Title Next starts writing before the template prompt

`45268D94-930B-4958-9988-094C85448418` shows a newly created entry with empty Title and the template heading “What did I finish?”, followed by writing space. The fixture template contains that heading and an empty paragraph. After entering a title and pressing the native Next key, the fixture immediately types its answer. In `F44B9D27-D643-4FF5-9C34-DDE59BF12BD4`, the reopened entry displays “Orchid project shipped.” above the prompt, in bold, rather than as a plain answer below it. The search excerpt independently reflects the same answer-before-prompt order.

Source supports the observed behavior: title submission sends `.focus`; native focus only makes the body first responder, and initial body selection begins at offset zero. The template document is copied without any explicit initial insertion target. This makes the straightforward title → Next → type path write into the beginning of the prompt instead of its prepared answer space. It is a usability defect even though both strings survive persistence.

A correction should define a one-time initial writing position for a newly template-created entry: prefer an existing empty ordinary paragraph as the answer target, with plain paragraph typing attributes. Preserve all template content/formatting, and preserve the user's later body selection when returning from the title. Do not silently append/reorder template blocks or jump the caret on every focus, title edit, reopening or image arrival. Specify behavior for templates with no empty paragraph, multiple prompt/answer sections, and blank entries before implementation, then obtain independent review of that concrete proposal. No new visible controls or instructions are needed.

The current test checks that both strings exist and that the first block is a heading; those assertions can accept this wrong order/style and may inadvertently encode it. The corrected behavioral assertion should verify the unchanged prompt before an ordinary answer paragraph, the intended insertion/caret behavior, and unchanged source template, alongside persistence. Actual normal/largest keyboard-focused captures should show the answer in its expected place.

### Native presentation and search

The new-entry and reopened editor captures keep writing primary: quiet surfaces, clear title/body hierarchy and a restrained native toolbar with formatting, image insertion and more actions. Nothing shown justifies extra onboarding text, permanent template controls or save indicators. The issue is initial insertion behavior rather than missing chrome.

`4DD52BA4-3DD2-440D-B225-A6A864CA29B5` shows the Work selector, dated result card, body excerpt and native active search field above the keyboard. “Orchid” is visibly searchable in entry content; the result has a clear title/date and enough excerpt to identify it. The OS close icon is a conventional search dismissal control, so the fixture's earlier assumption of a textual Cancel does not demonstrate a product defect. No additional search button, scope banner or replacement search UI is warranted by this screenshot. The selected Work journal supplies visible scope; actual cross-journal filtering is not established by this one capture.

### Evidence limits

The current source fixture intends to exercise default-template creation, title Next, body writing, scoped Work/Personal search, switching journals, relaunch and unchanged template/personal-entry content. It now accounts for the OS search close control and for journal switching opening an entry, but its corrected run was still pending when requested. These source intentions are not passing execution evidence. The three captures do not establish live focus/caret position, full keyboard interaction, largest text, empty search results, VoiceOver or Mac conventions. No blanket workflow acceptance is granted until the template insertion defect is addressed and the revised route is verified.

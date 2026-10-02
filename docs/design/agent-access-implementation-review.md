# Agent access implementation review

Date: 2026-09-20. Independent review against `agent-access.md` and `agent-access-review.md`. Inspected `AgentAccessView.swift`, `AgentController.swift`, `WindowSafety.swift`, and core `AgentAccess`, `AgentMCP`, and `AgentBridge`. No implementation edits or independently executed tests.

## Visual evidence and scope

Viewed `artifacts/agent-previews/C2436B18-29B1-408C-AB4B-63143E8FE406.png`: an **offscreen native NSHostingView render** of Agent Access with one grant and empty activity. It shows readable native typography, quiet grouped sections, sensible name/scope hierarchy, and concise copy without clipping. The layout is consistent with the proposal at the rendered size.

This is not interactive Mac screen QA. The Mac remains locked, and the blank detail artifact was not treated as evidence. No add/confirmation/detail/error state, keyboard behavior, VoiceOver, dark appearance, or enlarged text was visually inspected. The parent task reports passing native lifecycle tests for last-window close/reopen, actual loopback reads, revoke, and screen lock; this reviewer did not independently run those tests.

## Findings

1. **P2 — Report durable grant/revoke outcomes separately from refresh failures.** `AgentController.create` persists a grant and its connection file, then calls throwing `reload()`. If that later read fails, the add sheet says access could not be added and permits another Allow Read Access submission, even though a usable grant may already exist. `revoke` similarly commits revocation before throwing reload; the detail then says “Couldn’t revoke access.” Distinguish a failed commit from failed display/bridge restart. Once creation commits, surface that grant rather than inviting duplicate creation; once revocation commits, state that access was revoked, and offer retry only for reloading/restarting remaining access. The UI must describe the real permission state.
2. **P2 — Give actionable validation for implemented limits.** Core creation rejects names over 80 characters and more than 32 grants, but the form does not enforce/explain either limit. Both become “Couldn’t add access. Check the name and journals,” which can leave the user repeatedly retrying a valid-looking confirmation. Validate the name before confirmation and return focus to Name; when the grant limit is reached, explain that an existing access must be revoked before adding another. Do not show storage errors as name/scope errors.
3. **P2 — Copy acknowledgment is not the promised temporary accessible feedback.** Detail sets `copied = true` indefinitely. The “Copied” text has no explicit announcement and remains even after the clipboard changes. Make the acknowledgment brief, and verify that VoiceOver announces success without reading or logging credential contents. The instructions label must preserve access to the selectable text, not replace its accessible value with only “Connection Instructions.”
4. **P3 — Grant details are visually undiscoverable in the rendered section.** The grant row is a plain button that looks like static name/scope text. A native disclosure affordance or clear action treatment would make the route to instructions and revoke apparent. Keep the current quiet hierarchy; no custom styling is needed.
5. **P3 — Activity UI shows only 10 of the retained 100 events.** Core correctly retains 100, but the view uses `prefix(10)` with no route to the remainder. Either expose the remaining recent activity with a native disclosure/list or explicitly describe the displayed window as the latest 10. This is a completeness/clarity issue, not an access-control defect.

## Positive source observations

Consent appears before Allow Read Access with no preselected journals; final creation intersects selected stable IDs with live journals and core revalidates them. Detail includes creation time for duplicate names. Grants and activity are device-local encrypted state. Reads exclude unsaved text, deleted journals/entries, templates, images, history, and unresolved conflicts; search exposes an explicit truncation flag and read_entry supplies full text. MCP describes journal text as untrusted data and exposes only read-only tools.

The controller gates access on unlocked state, a live journal window, and no vault replacement. Closing the last registered window stops the bridge; session lock also stops it. Transport cancellation and core authorization checks protect suspended requests, and revoke stops pending bridge replies before changing durable permission state. Connection instructions carry executable/connection-file paths rather than a raw token or recovery key. These are source observations, not a comprehensive security audit.

## Outcome and remaining verification

The limited offscreen section render is consistent with the visual design. Resolve the permission-state/error findings before calling the management flow complete. Actual Mac interaction remains required for add/Back/Cancel, confirmation, details/revoke, clipboard feedback, duplicate names, long scopes, VoiceOver, keyboard focus, and lock with sheets open. Exercise post-commit reload failure and grant-limit/name validation with meaningful targeted checks. No offscreen render substitutes for these states.

## Detail layout refinement review — 2026-09-20

Viewed the additional **offscreen native** detail render `artifacts/agent-previews-final/9306E4CF-3124-47D6-AA05-B8962BF225B1.png`. It confirms that the full configuration text and long absolute paths occupy the initial sheet, pushing Copy/Revoke/Done out of the pictured area. This is limited layout evidence, not interactive QA.

**Approved refinement:** put the unchanged selectable guide inside a native DisclosureGroup labeled “Connection Instructions,” initially collapsed. Keep Copy Connection Instructions outside and directly below the disclosure; preserve clear Revoke Access and Done actions. Keep a short “Keep this connection file private.” explanation visible next to Copy so the credential-handling instruction is not only inside collapsed text. Full existing scope/provider disclosure stays in consent and the guide.

The action visibility requirement should survive expanding the guide and long journal lists: use native sheet toolbar/footer placement or a bounded scrolling content area for the guide, rather than letting all actions disappear below a very long text block. Do not impose a fixed height on explanatory text. Verify that the disclosure and selectable text are reachable with keyboard and VoiceOver, and that expanding/collapsing preserves sensible focus.

Adding a native disclosure chevron to the grant row is approved and resolves finding 4's discoverability issue. Showing all 100 retained activity events in the scrolling native Form is approved and resolves finding 5's hidden-history issue. No new consent step or design-review round is needed for these refinements. Reinspect the rendered result; actual Mac interaction/accessibility remains pending.

## Refined render and source recheck — 2026-09-20

Independently viewed these **offscreen native renders**:

- `artifacts/agent-previews-reviewed/04949622-F88B-4C9C-B860-4C146E16BA3D.png`: grant detail with collapsed Connection Instructions and separate action area.
- `artifacts/agent-previews-reviewed/70D6AC92-D054-46B1-A4CF-75DC2820E005.png`: Agent Access section with native row chevron.

**The refinement meets the approved layout at the rendered size.** Detail makes scope/status visible, keeps Copy and its privacy reminder beside the action, and places Revoke/Done outside the scrolling guide. The row chevron now communicates access to details. No overlap or clipping appears in these two renders. The large blank space in collapsed detail is ordinary flexible sheet space; no decoration or extra copy is needed.

Re-read the updated source:

1. **Finding 1 resolved in source:** creation returns its committed grant despite later reload failure; revocation removes the committed grant from the displayed list and treats reload failure separately. Neither path now throws a display-refresh failure back as a failed permission mutation. Verify the message and bridge recovery using actual post-commit failure injection; `resume()` may subsequently replace the more specific status with its generic bridge-start error, but it no longer invites duplicate grant creation through a failed-create return.
2. **Finding 2 resolved in source:** overlong names receive a concrete 80-character message and Name focus before confirmation; the 32-grant limit disables Add and explains the remedy. Generic persistence errors no longer blame name/scope validation.
3. **Finding 3 resolved in source:** Copy acknowledgment expires after two seconds and posts a short accessibility announcement; the selectable guide no longer overrides its accessible text with a generic label. Actual VoiceOver speech and clipboard behavior still require verification.
4. **Finding 4 resolved in the render/source:** a native chevron identifies the grant row as actionable.
5. **Finding 5 resolved in source:** the view presents all retained activity events instead of taking only ten. The supplied render has no events, so a populated scrolling list was not visually inspected.

The parent reports 9 native and 18 core tests passing, including actual stdio handshake, locked/revoked access, and stopping an in-flight bridge request. This reviewer did not rerun those tests. **No demonstrated material blocker remains from these findings.** The changes can move forward while retaining the original verification limits: interactive Mac use, expanded instructions at minimum size, large text/footer fit, populated activity, add/consent/errors, VoiceOver, and injected post-commit storage/read failures remain uninspected here. These offscreen renders do not complete interactive Mac QA.

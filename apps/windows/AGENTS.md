# Windows app: brief for the Windows agent

Read the root [AGENTS.md](../../AGENTS.md) first: the design gate, copy, test, security and hygiene rules there apply here, and so does "Working across platforms". This file is the starting brief for the Windows client. Nothing is built yet; the folder holds only this file and a README stub.

## Goal
A native Windows app with the same features, the same pages and the same copy as the Apple apps, built with WinUI 3, the Windows App SDK and C#, that feels as if Microsoft made it: Fluent 2, Windows 11 conventions, sentence-case labels, Windows Hello, standard dialogs, menus, shortcuts and Narrator support. Product rules are never traded for convention: data safety, quiet saving and syncing, plain copy, nothing silently discarded, nothing of the journals shown while locked. It must interoperate cleanly with the Apple apps and the server from other machines: same library formats, same sync, same archives.

You may be able to run and screenshot the Windows app but not the Apple apps. Work from the spec, the Apple notes, screenshots and source (read-only; you can read Swift without running it), and write what you build back so the next agent on any OS can port from it.

## Where to start
1. [spec/README.md](../../spec/README.md): how the spec is organized, the spec-first workflow, copy keys, command ids, and the checker (`python3 spec/tools/check-spec.py`, which must report 0 errors and 0 warnings).
2. [spec/platforms/windows/README.md](../../spec/platforms/windows/README.md), then [platform.md](../../spec/platforms/windows/platform.md) (the conventions every page follows), [commands.md](../../spec/platforms/windows/commands.md) and [index.md](../../spec/platforms/windows/index.md) (every page and its status). Each page is a mapping file with status `draft`, `reviewed` or `done`.
3. For the behaviour of a page: the spec page it maps; for how Apple implements it: [spec/platforms/apple/](../../spec/platforms/apple/README.md) and the Apple source named in the spec page's `sources:`.
4. [spec/open-questions.md](../../spec/open-questions.md): every open question. Decisions in the mapping files are proposals that you may refine with the owner so the app feels native on Windows; changes to behaviour, data rules or copy keys go through the spec first.

## Owner decisions already made
- Read [open-questions.md](../../spec/open-questions.md) D20 to D54 (the Windows decisions) and [review-2026-10-06.md](../../spec/platforms/windows/review-2026-10-06.md) (the independent design review of the whole Windows folder and what was adopted).
- On 2026-10-07 the owner accepted all of the reviewed Windows recommendations, with two changes:
  - **No OneDrive warning for plain Markdown export.** The person's risk; do not add the "Export to a OneDrive folder?" dialog or the checks behind it (D46 and B37 are settled).
  - **Tables must be fully editable in place, exactly like on the Mac.** This is a hard requirement for the editor technology choice, not a "should": a table that is only preserved or edited in source view does not pass. D33's read-only-grid fallback is withdrawn.
- Windows 11 (build 22000 or later) is the minimum, packaged as MSIX.
- The accepted recommendation for archives (one file instead of a directory package, D29) is a protocol change in `protocol/archive.md`. It needs a version bump and updated conformance fixtures, shared with the Apple client; do not ship a Windows-only archive format. Raise it with the owner before building archives.

## First milestone: the editor spike
Run the two editor spikes in parallel, time-boxed, against one shared scorecard: Spike A (`RichEditBox` plus an overlay layer behind an editor-surface interface) and Spike B (a `WebView2` block editor that serializes to Markdown). The pass and abandonment criteria are written in [entry-editor](../../spec/platforms/windows/screens/entry-editor.md) (The spikes), now with in-place table editing as a must for both: a spike that cannot edit tables in place with one shared undo history, Tab and Enter between cells, and Narrator reading the grid fails. Record scores, measurements and the recommendation in that file, and give the owner the result to decide (D30). Do not build other screens on a guess about the editor: the editor surface sits behind an interface so the document model and editing rules stay outside the control.

## Interoperability
- The wire, encryption, record, archive and Markdown formats are in [protocol/](../../protocol/README.md). The conformance fixtures in `protocol/conformance/` define correct behaviour; the Windows engine (sync, cryptography, document model, storage) must pass them in its own tests before any screen depends on it.
- Never change a protocol contract without bumping its version and updating the conformance fixtures; every other client must still pass them. Never rely on undocumented behaviour of the Apple client or the server: if the contract is silent, ask the owner and fix the contract.
- Preserve unknown fields and records you do not understand unchanged, and show them read-only. Never silently discard or overwrite content.
- Test against a real server (the container or `dotnet run`, [docs/development.md](../../docs/development.md)) and, when available, a library from another platform.

## Documenting back into the repository
- In the same change as the code, keep the page for each screen or flow current in [spec/platforms/windows/](../../spec/platforms/windows/README.md): the controls actually used, layout at each window width, shortcuts, copy differences, accessibility results, source files (`sources:`), and status (`draft`, `reviewed` after the design gate, `done` after the running app was inspected against the page).
- Screenshots go in `spec/platforms/windows/screenshots/<device>/<id>-<state>.png`, listed under `screenshots:` in the page's front matter, produced by a capture script (under `design/`, written for Windows) and not by hand. Use the seeded sample library only. See [spec/platforms/README.md](../../spec/platforms/README.md).
- Update `windows:` in [parity.yaml](../../spec/parity.yaml) when a feature ships or differs by design, with the reason.
- The design gate in the root AGENTS.md applies to every screen: write the design from the page, have an independent design agent review it, address the findings, implement, then inspect the real UI.
- Add the solution layout, build and test commands, and the mise or other toolchain pins to this folder's README.md as they exist, and any Windows-specific rules to this file. Check in any new tool version or dependency with a documented reason, and keep lockfiles.

## When a feature starts on Windows
A feature may originate on Windows and be ported to Apple later. Specify it first: add or change the spec page (screen, flow, messages, commands, copy keys in `copy/en.json`), add the `parity.yaml` entry with `reference: windows`, record questions in `open-questions.md`, then implement. The Apple and Android agents will port from your page, screenshots and source, so write them for a reader who cannot run your app. A change to existing behaviour that you think the spec should make is a proposal to the owner, not an edit you make alone.

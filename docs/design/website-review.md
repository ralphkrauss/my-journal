# Public website — independent review

2026-09-27. Scope: independent design review of [website.md](website.md) before implementation, and a second review of the implemented pages in `website/`.

An independent design agent received the requirements and the proposal, not the author's reasoning, and checked the copy against README.md, SECURITY.md, docs/architecture.md, docs/distribution.md, the protocol, the privacy manifest, the issue templates and the app code. For the second review it read the implemented pages, opened them in a browser, tabbed through them and inspected light, dark, desktop, phone and 320 px screenshots. It didn't edit anything.

## First review: approve with changes

Required changes, all applied:

- **Accuracy.** App Lock needs a PIN, with Face ID or Touch ID as an optional way to unlock. Agent access works only while a My Journal window is open and unlocked, and any agent that can read files on the Mac can use every connection. The server list now matches SECURITY.md in full (versions kept permanently, sizes that show entry length, probable permanent deletions, device names that often include the owner's name, how devices were added and revoked, sync frequency) and no longer says the server can't see dates. Delete Permanently reaches other devices when they sync, keeps images in the app's storage, and doesn't erase server history, backups or archives. Removing a device starts with Revoke Access. Images from any source lose their location, and the camera is iPhone and iPad only. Adding a device covers the master password route and asks people to compare the check code.
- **Missing policy content.** Retention ("Nothing is deleted automatically"), archives, system writing features (Dictation, Writing Tools, third-party keyboards), and a consistent statement about the only personal data the developer can hold: support emails and issues.
- **Questions had no route.** The repository's issue forms are bug reports and feature requests only, so questions go to email, which also serves App Store buyers without a GitHub account.
- **App Store placeholder.** The non-interactive pill looked like a button or badge; availability is plain text.
- **Support warning** moved before the links.
- **Visual and accessibility.** Missing dark hairline and callout tokens, underlines on every content link, a header that wraps, root sizes in `rem`, iOS Text Size support, `main` focusable from the skip link, solid cards instead of translucent ones, a visible icon edge, 384 px icon source, footer as a list, trademark credit, `theme-color`, Open Graph tags and a not-found page.

Kept as proposed, with reasons:

- **Mac features.** The review noted that a Mac App Store build must be sandboxed and that the bundled server, `journal-agent` and the data folder location haven't been adapted to that. The site describes the current app, where all three are true. The Mac data folder is described as "inside your user Library folder", which holds for both. See the owner items below.
- **Device backups.** The suggested "but not its key" isn't true for Developer ID Mac builds, which keep the key in the login keychain that Time Machine backs up, so the policy says only that journal content in backups stays encrypted.
- **Country in the contact details** isn't stated until the owner confirms it.
- **Dark palette** stays deep navy, as the owner asked, rather than near-neutral.
- **Serial comma.** The site follows the repository's existing style (no serial comma).

## Second review: approve with changes

Required, applied: the first "In short" bullet now says the app doesn't collect personal data or send anything to the developer, because TestFlight collects crash logs and usage data automatically; the TestFlight sentence mentions device details.

Suggested, applied: clearer first paragraph under "On your devices" (settings aren't encrypted), the GitHub Pages documentation link for IP logging, clearer deletion and contact sentences, no line breaks inside menu paths, "No analytics, ads or tracking." on the home page, tighter header spacing so all pages keep a one-row header at 320 px, hairlines aligned with the content, balanced wrapping of headings and hero text, `100svh`, and print colours for cards and hairlines.

The reviewer confirmed that every text colour passes AA in both appearances (most pass AAA), the skip link and focus ring work, the header reflows, and every contents link matches its section.

## Owner items

- Before the App Store launch, verify on the sandboxed Mac build: the bundled server ("a server you run on a Mac"), agent access, and the data folder location in the privacy policy. Update docs/distribution.md, which still describes a Developer ID Mac download on GitHub Releases.
- Consider an in-app command to erase a device; Keychain items stay after the app is deleted.
- Consider showing the app version in iPhone and iPad Settings, which the support page asks for.
- Consider an issue form or Discussions for questions if GitHub should handle them.
- Consider whether to limit Writing Tools or third-party keyboards in the editor.
- Links to repository files and the policy's history return 404 until the repository is pushed.

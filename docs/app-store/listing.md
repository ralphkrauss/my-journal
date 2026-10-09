# App Store listing

Text for the App Store Connect record of My Journal, ready to paste. Primary language: English (U.S.). Written on 2026-10-05 against build 16 (version 1.0) and checked against the code; recheck every claim against the build you submit. Field-by-field entry order is in [launch-checklist.md](launch-checklist.md).

One app record holds both platforms (universal purchase, bundle ID `io.github.ralphkrauss.myjournal`). Name, subtitle, categories, content rights, the privacy policy URL and the age rating are set once for the app. Description, keywords, promotional text, support and marketing URLs, copyright and screenshots are set per platform version, so the iOS and macOS versions each get their own copy below; text doesn't carry over when the macOS platform is added ([required, localizable and editable properties](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties), [add platforms](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms)).

## Audience

Most people who want a journal will use the notes app on their phone or a large all-in-one app, and this listing doesn't try to win them. It's written for the people who go looking for what My Journal is: privacy and end-to-end encryption, self-hosting and data ownership, open source and plain Markdown, native apps that stay simple, no subscription and no account, and AI on their own terms. Many are technical or semi-technical: self-hosters, privacy-minded professionals, developers, and writers who care about their tools.

So the promotional text and the first lines of each description say those things first, in plain words, before the feature lists; the keywords are what these people search for; and the first three screenshots say "end-to-end encrypted", "your server, or none" and "native and simple" ([screenshots-plan.md](screenshots-plan.md#the-story)).

The statement of who it's for, reused in the README, the descriptions and launch posts:

> My Journal is for people who want to own their writing: who would rather run their own server than trust someone else’s cloud, want end-to-end encryption without an account or a subscription, prefer open source and plain Markdown, and like native apps that stay simple. If you want sync that works with no setup at all, or a large all-in-one notes app, another app will suit you better.

## Limits and counts

Counted with Python on the exact text in the code blocks below (characters are Unicode code points; bytes are UTF-8). Recount after any edit:

```sh
python3 -c 'import sys; s=sys.stdin.read().rstrip("\n"); print(len(s), "characters,", len(s.encode()), "bytes")' < file
```

| Field | Limit | This copy | Source |
| --- | --- | --- | --- |
| Name | 30 characters | 26 characters | [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) |
| Subtitle | 30 characters | 28 characters | [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) |
| Promotional text | 170 characters | 144 characters | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) |
| Description, iOS | 4000 characters | 3508 characters (3564 bytes) | same |
| Description, macOS | 4000 characters | 3682 characters (3736 bytes) | same |
| Keywords | 100 bytes, comma-separated, no spaces after commas, each longer than 2 characters | 97 bytes, 13 keywords; English (U.K.) set 100 bytes, 11 keywords | same; [App Store search](https://developer.apple.com/app-store/search/) |
| What's New | Not shown for the first version | 593 characters, for TestFlight and GitHub | same |

Metadata rules that shaped this copy (guidelines [2.3.7](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) and 2.3.10): no other apps', companies' or AI products' names; no prices in the name, subtitle, screenshots or previews; no unverifiable claims; no other mobile platforms, so the planned Windows, Android and Linux apps aren't mentioned. The case for My Journal is made with plain facts instead: no account, no subscription, your server or none, open source, Markdown. The promotional text and the "One purchase" paragraph say "no subscription" without naming a price, as many approved apps do; if App Review objects, remove it from the promotional text first.

## App information (both platforms)

| Field | Value |
| --- | --- |
| Name | `My Journal – Private Diary` (the dash is an en dash, U+2013, so 26 characters are 28 bytes) |
| Subtitle | `Simple, encrypted, and yours` |
| Primary category | Lifestyle |
| Secondary category | Productivity (recommended; see below) |
| Content rights | No, it doesn't contain, show or access third-party content. |
| Privacy Policy URL | `https://github.com/ralphkrauss/my-journal/blob/main/PRIVACY.md` |
| Age rating | 4+, see [age-rating.md](age-rating.md) |
| App Privacy | Data Not Collected, see [app-privacy.md](app-privacy.md) |

The home screen name stays "My Journal" (`CFBundleDisplayName`).

### Category

Recommendation: **Lifestyle** primary, **Productivity** secondary. The secondary category is optional and the owner's choice.

Apple asks for the category that describes the app's main purpose, where people would look for it, and where similar apps are ([Choosing a category](https://developer.apple.com/app-store/categories/)).

- Lifestyle is "general-interest subject matter", and personal journaling is the main use. The Mac app already declares `LSApplicationCategoryType` = `public.app-category.lifestyle` in `apps/apple/project.yml`, which matches.
- Productivity lists note taking among its examples, and My Journal is for work notes too (separate work journals, your own work templates, checklists). As secondary, the app also appears in Productivity browsing; as primary, it would sit among task managers and large document tools.
- Not recommended: Health & Fitness. Some journaling apps use it for mood and wellbeing tracking, which My Journal doesn't have, and since March 2026 apps in that category distributed in the EU, UK or US must declare their regulated medical device status ([App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)).
- Leaving the secondary category empty is also fine; it affects only where the app appears when people browse.

## iPhone and iPad (iOS platform version)

### Promotional text

Can be changed at any time without a new version, and isn't used for search.

```text
End-to-end encrypted. Sync through your own server, or not at all. No account, no subscription. Open source, and native on iPhone, iPad and Mac.
```

### Description

```text
End-to-end encrypted, with no account and no subscription. Sync through a server you run, or not at all. Open source, with your entries in Markdown. Native on iPhone, iPad and Mac.

My Journal is a simple, private journal for people who want to own their writing. It does the basics well, with a clean interface that stays out of the way.

PRIVACY
• No account and no sign-up. No analytics, ads or tracking.
• Entries, journal names, templates, images and image descriptions are encrypted on your device, with a key protected by your master password. Your server never sees the password or the key.
• App Lock with Face ID, Touch ID or your passcode. While it’s on, the app switcher doesn’t show your journals.
• Location data is removed from photos you add.
• Works offline. Everything is saved on your device first.
• Erase Journals and Settings removes all journals and settings from this device.

YOUR SERVER, OR NONE
• Sync is optional and needs a server you set up: the open-source server, on a home server, a computer you keep on, or a hosting service you choose. Your server stores only encrypted data it can’t read.
• Your iPhone and iPad reach it over a private network you set up, such as a VPN, or over HTTPS.
• Add an iPhone or iPad by scanning a code on a device you already use, or any device by entering your master password.
• Sync works quietly and tells you only when something needs attention.
• If an entry changes on two devices before they sync, both versions are kept as separate entries. Nothing is overwritten.

OPEN AND PORTABLE
• The apps and the sync server are open source under the Apache License 2.0. You can build them yourself.
• Entries are written in Markdown, which you can view in the app. The sync, encryption and archive formats are documented.
• Export all your journals, with images and earlier versions, to one archive, encrypted with your master password, and restore it in My Journal on any of your devices.
• Export your journals as Markdown files, with their images, for any app.

WRITE
• Headings, bold, italic, lists with indentation, checklists, quotes, code, tables and links.
• Add several photos at once, from your library, your files or the camera. Describe them for VoiceOver, and copy, share, save or delete them.
• Markdown shortcuts as you type, and the Markdown of any entry one tap away.
• Create your own templates and start an entry from one inside a new entry.

ORGANIZE
• Keep separate journals, for example one personal and one for work, in the order you choose.
• Pin the entries you come back to.
• Search all your entries.
• Version History restores an earlier version of an entry, and Recently Deleted brings back what you deleted.

AGENT ACCESS, ON YOUR TERMS
Let an AI agent you already use read the journals you choose through your own server, then ask it about a month, a habit or a pattern. Agents connect with the Model Context Protocol (MCP). Access is off until you allow it, read-only, set per journal and revocable at any time. My Journal has no AI service built in; an agent that uses an online service sends what it reads to that service.

ONE PURCHASE
One purchase covers iPhone, iPad and Mac, with no subscription and no in-app purchases.

WHO IT’S FOR
People who want to own their writing: who would rather run their own server than trust someone else’s cloud, and who like apps that stay simple. If you want sync that works with no setup at all, another app will suit you better. The user guide explains each server option.
```

### Keywords

```text
markdown,self-hosted,open source,e2ee,privacy,secure,offline,local,notes,encryption,sync,foss,mcp
```

Chosen for the people this app is for (see [Audience](#audience)): words they type when they look for exactly this kind of app, and that combine with the name and subtitle, which Apple indexes too, into searches such as "encrypted markdown journal", "self-hosted journal", "open source diary", "private offline notes" or "e2ee journal".

| Keyword | Why |
| --- | --- |
| markdown | The storage format; people who want plain-text portability search for it. |
| self-hosted | The defining feature for self-hosters. |
| open source, foss | Both spellings are in use; "foss" costs 4 bytes. |
| e2ee, encryption | The short form privacy people use, and the noun, which differs from the subtitle's "encrypted". |
| privacy, secure | Combine with "journal" and "diary" from the name. |
| offline, local | For people who want their writing on the device first. |
| notes | Broad on its own, but it combines into "encrypted notes", "markdown notes" and "private notes". |
| sync | Combines into "self-hosted sync" and "encrypted sync". |
| mcp | A small, exact audience: people who connect their own AI agents. |

Left out on purpose:

- Words already in the name, subtitle or categories (my, journal, private, diary, simple, encrypted, yours, lifestyle, productivity), which Apple already indexes and asks you not to repeat ([Creating your product page](https://developer.apple.com/app-store/product-page/)).
- The broad journaling words of the earlier set (daily, reflection, gratitude, writing, notebook). They compete with the largest journaling apps and bring buyers who expect prompts, mood tracking and sync without setup, which leads to poor reviews.
- "no subscription" and other pricing words. The promotional text and description say it; keywords that describe pricing risk guideline 2.3.7.
- Other apps', companies' and services' names, including the VPN the user guide recommends, and words of two characters or fewer, such as "AI".

### Other fields

| Field | Value |
| --- | --- |
| Support URL | `https://github.com/ralphkrauss/my-journal/blob/main/SUPPORT.md` |
| Marketing URL | `https://github.com/ralphkrauss/my-journal` |
| Copyright | `2026 Ralph Krauss` (App Store Connect shows it after ©) |
| Version | `1.0` (`MARKETING_VERSION` in `apps/apple/project.yml`) |

All four GitHub addresses in this file answered HTTP 200 without signing in on 2026-10-05. They point at `main`, so renaming or moving PRIVACY.md or SUPPORT.md breaks them until App Store Connect is updated.

## Mac (macOS platform version)

Promotional text, keywords, support URL, marketing URL, copyright and version are the same as for iPhone and iPad; enter them again for the macOS version.

### Description

```text
End-to-end encrypted, with no account and no subscription. Sync through a server you run, or not at all. Open source, with your entries in Markdown. Native on Mac, iPhone and iPad.

My Journal is a simple, private journal for people who want to own their writing. It fits in on the Mac: your journals in the sidebar, a list of entries, and room to write, with the menus and keyboard shortcuts you expect.

PRIVACY
• No account and no sign-up. No analytics, ads or tracking.
• Entries, journal names, templates, images and image descriptions are encrypted on your Mac, with a key protected by your master password. Your server never sees the password or the key.
• App Lock with Touch ID or your login password. My Journal locks after 30 minutes without use (you can choose), and when your Mac sleeps, its screen locks or you switch users.
• Location data is removed from photos you add.
• Works offline. Everything is saved on your Mac first.
• Erase Journals and Settings removes all journals and settings from this Mac.

YOUR SERVER, OR NONE
• Sync is optional and needs a server you set up. Your server stores only encrypted data it can’t read.
• Run the open-source server on a home server, a computer you keep on, or a hosting service you choose. Your Mac, iPhone and iPad reach it over a private network you set up, such as a VPN, or over HTTPS.
• Add a device by entering your master password, or by approving it on a device you already use and checking that both show the same code.
• Sync works quietly and tells you only when something needs attention.
• If an entry changes on two devices before they sync, both versions are kept as separate entries. Nothing is overwritten.

OPEN AND PORTABLE
• The apps and the sync server are open source under the Apache License 2.0. You can build them yourself.
• Entries are written in Markdown, which you can view in the app. The sync, encryption and archive formats are documented.
• Export all your journals, with images and earlier versions, to one archive, encrypted with your master password, and restore it in My Journal on any of your devices.
• Export your journals as Markdown files, with their images, for any app.

WRITE
• Headings, bold, italic, lists with indentation, checklists, quotes, code, tables and links.
• Drag in or insert several images at once. Describe them for VoiceOver, and copy, share, save or delete them.
• Markdown shortcuts as you type, and the Markdown of any entry one click away.
• Create your own templates and start an entry from one inside a new entry.
• Show Editor Only hides the sidebar and list when you want to focus.

ORGANIZE
• Keep separate journals, for example one personal and one for work, in the order you choose.
• Pin the entries you come back to.
• Search all your entries, and find and replace within one.
• Version History restores an earlier version of an entry, and Recently Deleted brings back what you deleted.

AGENT ACCESS, ON YOUR TERMS
Let an AI agent you already use read the journals you choose, then ask it about a month, a habit or a pattern. Agents connect to your own server with the Model Context Protocol (MCP). Access is off until you allow it, read-only, set per journal and revocable at any time. My Journal has no AI service built in; an agent that uses an online service sends what it reads to that service.

ONE PURCHASE
One purchase covers Mac, iPhone and iPad, with no subscription and no in-app purchases.

WHO IT’S FOR
People who want to own their writing: who would rather run their own server than trust someone else’s cloud, and who like apps that stay simple. If you want sync that works with no setup at all, another app will suit you better.
```

The Mac app is only a client and runs on Apple silicon and Intel Macs, so the Mac description makes no claim about the Mac running a server. People who want a server on a Mac run the container there ([self-hosting](../self-hosting/README.md#running-the-server-on-a-mac)).

## English (U.K.) localization

Add English (U.K.) as a second localization of both platform versions. It's the default App Store language in several European storefronts and an added language in others ([App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations)), and it gives a second 100-byte keyword field there. Whether a storefront combines the keywords of its localizations isn't documented by Apple, so the U.K. set doesn't rely on it: it stands on its own and doesn't repeat the U.S. set.

| Field | Value |
| --- | --- |
| Name, Subtitle | The same as English (U.S.) |
| Promotional text | The same as English (U.S.) (no spelling differences) |
| Description | The U.S. descriptions with British spelling: "ORGANIZE" becomes "ORGANISE"; nothing else differs. (3506 and 3680 characters) |
| Support URL, Marketing URL | The same |

Keywords (English (U.K.), both platforms, 100 bytes):

```text
zero-knowledge,end-to-end,local-first,plain text,vault,lock,password,server,agent,homelab,journaling
```

| Keyword | Why |
| --- | --- |
| zero-knowledge, end-to-end | How privacy-minded people describe a server that can't read their data. |
| local-first, plain text | The local-first and plain-text communities' own terms. |
| vault, lock, password | Searches for a journal that's locked and protected. |
| server, homelab | Self-hosters' terms; "server" combines into "journal server" and "sync server". |
| agent | For people looking for a journal their own AI agent can read; "AI" alone is too short to be a keyword. |
| journaling | The activity, which may not match "journal" in the name. |

## What's New

App Store Connect doesn't show What's New for the first version of an app ([Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)). Use this text for TestFlight's What to Test and the GitHub release notes, and write a new one for 1.0.1.

```text
The first release of My Journal for iPhone, iPad and Mac.

• Write with formatting, checklists, indented lists, tables, links and photos, in separate journals, with templates you create.
• Pin entries, order your journals, search, and restore from Version History and Recently Deleted.
• Export your journals as Markdown files, with their images, for any app.
• End-to-end encryption on by default, App Lock, and no account.
• Optional sync through a server you run, such as a home server or a computer you keep on.
• Read-only agent access to the journals you choose, through your own server.
```

## Claims checked against build 16

Every feature in the descriptions was checked in the code on 2026-10-05. The template and sync rows were changed on 2026-10-09 for release 1.1, which removes a journal's default template; recheck them against the 1.1 code before submitting:

| Claim | Where |
| --- | --- |
| Headings, bold, italic, lists, checklists, quotes, code, tables, links; Increase and Decrease Indent | `AppCommands.swift`, `FormattingPopover.swift` |
| Several photos at once from Photo Library, Take Photo or Choose File…; Copy, Share…, Save to Photos, Image Descriptions…, Delete (Mac: Cut, Copy, Paste, Share, Save Image As…) | `WritingAccessory.swift`, `ImagePickerPresenter.swift`, `ImageActionsIOS.swift`, `ImageActionsMac.swift` |
| Location removed from added photos | `ImportedImage.swift` |
| Templates you create, used from inside a new entry (no default template per journal since 1.1); new libraries start without templates | `no-built-in-templates-2026-10-04.md`, `1-1-library-simplifications.md` (M), `TemplateChooserView.swift` |
| Journal order, Pin Entry and the Pinned section | `journal-order.md`, `pinned-entries.md`, `JournalNavigation.swift` |
| Search, Version History, Recently Deleted with Delete All | `RootView.swift`, `ios-delete-all-and-settings-2026-10-03.md` |
| Encryption on by default (Use Encryption is the suggested choice on the first screen) | `CreateJournalView.swift` |
| App Lock with Face ID, Touch ID or the passcode (no PIN); Mac locks after inactivity (30 minutes by default), on sleep and on switching users | `AppLockSettings.swift`, `InactivityLockSettings.swift` |
| Erase Journals and Settings | `EraseSection.swift` (build 16) |
| Sync only through the person's server, which the apps don't include (since 2026-10-05); scanning a code; entries, templates, journals and deletions that differ settle themselves, keeping both versions (a notice and Changed on Two Devices say so); quiet sync status | `ServerClient.swift`, `SettingsView.swift`, `AddDeviceView.swift`, `client-only-mac-lists-markdown-2026-10-05.md`, `quiet-sync-and-title-alignment.md` |
| Agent access on every platform through the person's server, read-only, per journal, revocable | `ServerAgentsView.swift`, `agent-access-simplified.md` |
| Export as Markdown, with images (build 17) | `MarkdownExportView.swift`, `JournalCore/MarkdownExport.swift`, [protocol/markdown-export.md](../../protocol/markdown-export.md) |
| No analytics, ads or tracking | [app-privacy.md](app-privacy.md) |

Not claimed: exporting a single entry as a Markdown file. Export as Markdown (build 17) exports all journals at once; the archive is a SQLite package, not a folder of Markdown files ([protocol/archive.md](../../protocol/archive.md)).

## Accessibility Nutrition Labels (optional)

App Store Connect lets you declare accessibility features. Apple says the labels are voluntary for now and will become required later. A feature may be declared only if people can complete all common tasks with it: first launch, writing, and Settings ([Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)).

| Feature | Candidate? | Before declaring |
| --- | --- | --- |
| Dark Interface | Yes | The app follows system appearance; check every sheet in dark mode. |
| VoiceOver | Likely | Walk through first launch, writing, templates, Settings and Agent Access with VoiceOver on each platform. |
| Voice Control | Unverified | Test the same tasks with Voice Control. |
| Larger Text (iPhone and iPad only) | Likely | Check the largest accessibility sizes on the first screen, in the editor and in Settings. |
| Sufficient Contrast | Unverified | Check with Increase Contrast. |
| Reduced Motion | Likely | Check with Reduce Motion. |
| Differentiate Without Color Alone | Likely | Check conflict and error states. |
| Captions, Audio Descriptions | Not applicable | The app has no video or audio content. |

Declare nothing that hasn't been checked on the submitted build. Leaving the labels empty doesn't hold up review.

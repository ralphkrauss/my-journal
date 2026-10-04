# App Store listing

Text for the App Store Connect record of My Journal, ready to paste. Primary language: English (U.S.). Checked against the app and the [user guide](../guide/README.md) on 2026-09-28; recheck every claim against the build you submit.

One app record holds both platforms (universal purchase, bundle ID `io.github.ralphkrauss.myjournal`). Name, subtitle, categories, the privacy policy URL and the age rating are set once for the app. Description, keywords, promotional text, support and marketing URLs, copyright, What's New and screenshots are set per platform version, so the iOS and macOS versions each get their own copy below ([required, localizable and editable properties](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties)).

## Limits

| Field | Limit | Source |
| --- | --- | --- |
| Name | 2 to 30 characters | [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information); guideline [2.3.7](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) |
| Subtitle | 30 characters | [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) |
| Promotional text | 170 characters; can be changed without a new version; not used for search | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information), [Creating your product page](https://developer.apple.com/app-store/product-page/) |
| Description | 4000 characters, plain text | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) |
| Keywords | 100 bytes, comma-separated, each longer than 2 characters; don't repeat the app or company name | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) |
| What's New | 4000 characters; required for every version after the first | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) |
| Review notes | 4000 bytes | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) |

Metadata rules that shaped this copy (guideline [2.3.7](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) and [2.3.10](https://developer.apple.com/app-store/review/guidelines/)): no prices or pricing terms in the name, subtitle, screenshots or previews; no other apps' names or trademarks in the subtitle or keywords; no unverifiable claims; no other mobile platforms. So the planned Windows, Android and Linux apps aren't mentioned, and AI products aren't named. The description's "One purchase" paragraph states how the app is sold without a price; drop it if App Review objects.

## App information (both platforms)

| Field | Value | Length |
| --- | --- | --- |
| Name | `My Journal – Private Diary` | 26 characters (the dash is an en dash, U+2013) |
| Subtitle | `Simple, encrypted, and yours` | 28 characters |
| Primary category | Lifestyle | |
| Secondary category | Productivity | |
| Privacy Policy URL | `https://github.com/ralphkrauss/my-journal/blob/main/PRIVACY.md` | |
| Content rights | No, the app doesn't contain, show or access third-party content. | |
| Age rating | 4+, see [age-rating.md](age-rating.md) | |

The home screen name stays "My Journal" (`CFBundleDisplayName`).

### Category

Recommendation: **Lifestyle** primary, **Productivity** secondary.

Apple asks for the category that describes the app's main purpose, where people would look for it, and where similar apps are ([Choosing a category](https://developer.apple.com/app-store/categories/)).

- Lifestyle is "general-interest subject matter", and personal journaling is the main use. Journey is listed under Lifestyle.
- Productivity lists note taking among its examples, and My Journal is for work notes too (templates for work notes, separate work journals). It fits as the secondary category, where the app still appears in category browsing and filters. As primary, it would put a deliberately small journal among task managers, email clients and large note and document tools.
- Apple's Journal and Day One are listed under Health & Fitness (checked 2026-09-28). That category suits mood and wellbeing tracking, which My Journal doesn't have, and in the EU it requires a declaration about regulated medical devices ([App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)). Not recommended.
- The Mac app already declares `LSApplicationCategoryType` = `public.app-category.lifestyle` in `apps/apple/project.yml`, which matches.

## iPhone and iPad (iOS platform version)

### Promotional text

```text
A private journal that stays simple. No account, encrypted by default, and synced only through a server you run, or not at all.
```

(127 characters)

### Description

```text
My Journal is a private journal with a clean, simple interface. Write, add photos and find things again, with no account and no company server in between.

SIMPLE ON PURPOSE
• Write with headings, lists, checklists, quotes, links, tables and images. Markdown shortcuts work as you type, and your spelling and correction settings apply.
• Keep separate journals, for example one for personal notes and one for work.
• Save your own templates and start entries from them. Each journal can have a default template.
• Search your entries, restore an earlier version from Version History, and bring back what you deleted from Recently Deleted.
• Works offline. Everything is saved on your device first.

YOUR DATA STAYS YOURS
• No account and no sign-up. There are no analytics, ads or tracking.
• Encryption is on by default. Entries, journal names, templates, image descriptions and images are encrypted on your device, with a key protected by your master password.
• Sync is optional, and only through a server you run: on your Mac, on a home server, or with a host you choose. With encryption on, your server stores your journals in a form it can’t read.
• Add a device by approving it on one you already use and checking that both show the same code.
• If an entry changes on two devices before they sync, both versions are kept for you to review.
• App Lock with a PIN, and Face ID or Touch ID.
• Export all your journals to an archive, and restore it later.
• When you add a photo, where it was taken is removed.

INSIGHTS FROM YOUR OWN WRITING, ON THE MAC
With My Journal on your Mac, you can let an AI agent you already use read the journals you choose, then ask it about a month, a habit or a pattern. Agents connect through the Model Context Protocol (MCP). Access is off until you add it, read-only, set per journal and revocable, and works only while My Journal is open and unlocked on the Mac. It isn’t available on iPhone or iPad. My Journal has no AI service built in; an agent that uses an online service sends what it reads to that service.

OPEN SOURCE
The apps and the sync server are open source under the Apache License 2.0. Entries are written in standard Markdown, and the sync, encryption and archive formats are documented. You can also build My Journal from source yourself.

ONE PURCHASE
One purchase covers iPhone, iPad and Mac, with no subscription and no in-app purchases.

Sync needs a server you set up yourself. The open-source server runs on a Mac with macOS 14 or later, on Linux, or in a container. The user guide explains each option.
```

(2641 characters.)

### Keywords

```text
markdown,notes,notebook,daily,reflection,gratitude,writing,secure,offline,self-hosted,open source
```

(97 bytes.) Left out on purpose: words already in the name or subtitle (my, journal, private, diary, simple, encrypted, yours), which Apple already indexes; competitor and AI product names; "mood", "planner" and "AI", which describe features the app doesn't have or are too short.

### What's New (draft)

App Store Connect doesn't ask for What's New on the first version of an app. Use this text for the TestFlight "What to Test" field and the GitHub release notes, and adapt it for 1.0.1.

```text
The first release of My Journal for iPhone, iPad and Mac.

• Write with formatting, images and links, in separate journals, with templates.
• Encryption on by default, with no account.
• Optional sync through a server you run, with device pairing and review of changes made on two devices.
• Search, Version History, Recently Deleted, App Lock and archive backups.
• On the Mac, read-only agent access to the journals you choose.
```

### Other fields

| Field | Value |
| --- | --- |
| Support URL | `https://github.com/ralphkrauss/my-journal/blob/main/SUPPORT.md` |
| Marketing URL | `https://github.com/ralphkrauss/my-journal` |
| Copyright | `2026 Ralph Krauss` (App Store Connect adds ©) |
| Version | Match `MARKETING_VERSION` in `apps/apple/project.yml` (currently 0.1.0; set 1.0.0 for launch). |

The URLs work only once the repository is public ([release operations](../release-operations.md#app-store-connect)).

## Mac (macOS platform version)

Promotional text, support URL, marketing URL, copyright and What's New are the same as for iPhone and iPad.

### Description

```text
My Journal is a private journal with a clean, simple interface that fits in on the Mac: a sidebar for your journals, a list of entries, and room to write, with the menus and keyboard shortcuts you expect. No account and no company server.

SIMPLE ON PURPOSE
• Write with headings, lists, checklists, quotes, links, tables and images. Markdown shortcuts work as you type, and your spelling and correction settings apply.
• Keep separate journals, for example one for personal notes and one for work.
• Save your own templates and start entries from them. Each journal can have a default template.
• Search your entries, restore an earlier version from Version History, and bring back what you deleted from Recently Deleted.
• Works offline. Everything is saved on your Mac first.

INSIGHTS FROM YOUR OWN WRITING
Let an AI agent you already use read the journals you choose, then ask it about a month, a habit or a pattern. Agents connect through the Model Context Protocol (MCP), using a connector included in the app.
• Off until you add it in Settings > Agent Access.
• Read-only: an agent can list, search and read entries in the journals you chose, and can’t change anything.
• Per journal, and revocable at any time. Recent Activity lists each agent’s recent requests.
• Works only while a My Journal window is open and unlocked.
My Journal has no AI service built in. An agent that uses an online service sends what it reads to that service.

YOUR DATA STAYS YOURS
• No account and no sign-up. There are no analytics, ads or tracking.
• Encryption is on by default. Entries, journal names, templates, image descriptions and images are encrypted on your Mac, with a key protected by your master password.
• Sync is optional, and only through a server you run. Your Mac can be that server: Use This Mac starts the server included in the app, and with Tailscale your iPhone and iPad can reach it privately. You can also use a home server or a host you choose.
• With encryption on, your server stores your journals in a form it can’t read.
• Add a device by approving it on one you already use and checking that both show the same code.
• If an entry changes on two devices before they sync, both versions are kept for you to review.
• App Lock with a PIN and Touch ID. With App Lock on, My Journal locks when your Mac does.
• Export all your journals to an archive, and restore it later.

OPEN SOURCE
The apps and the sync server are open source under the Apache License 2.0. Entries are written in standard Markdown, and the sync, encryption and archive formats are documented. You can also build My Journal from source yourself.

ONE PURCHASE
One purchase covers iPhone, iPad and Mac, with no subscription and no in-app purchases.

Using this Mac as a sync server requires macOS 14 or later.
```

(2870 characters.)

### Keywords

```text
markdown,notes,notebook,daily,reflection,gratitude,writing,secure,offline,self-hosted,open source
```

Same as iOS. An alternative that leans on agent access, if search data later favors it: `markdown,notes,daily,reflection,gratitude,writing,secure,offline,self-hosted,open source,mcp,agent` (97 bytes).

## Before submitting

- Check each description bullet against the build: in particular tables, checklists, Touch ID on the Mac, and whether the Mac build ships the server for Intel Macs (an open owner decision in the Mac App Store sandbox record). If "Use This Mac" isn't available on Intel Macs, add "Using this Mac as a sync server requires a Mac with Apple silicon and macOS 14 or later."
- Count lengths again after any edit: `python3 -c 'import sys; s=sys.stdin.read().rstrip("\n"); print(len(s), len(s.encode()))' < file`.
- Keep the description free of prices, and keep screenshots and previews free of pricing words (guideline 2.3.7).

## Accessibility Nutrition Labels (optional for now)

App Store Connect lets you declare accessibility features. A feature may be declared only if people can complete all common tasks with it: first launch, writing, and Settings ([Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)). Apple says these will become required.

| Feature | Candidate? | Before declaring |
| --- | --- | --- |
| Dark Interface | Yes | The app follows system appearance; check every sheet in dark mode. |
| VoiceOver | Likely | Walk through onboarding, writing, templates, Settings and Agent Access with VoiceOver on each platform. |
| Voice Control | Unverified | Test the same tasks with Voice Control. |
| Larger Text (iPhone and iPad only) | Likely | Check the largest accessibility sizes in onboarding, the editor and Settings. |
| Sufficient Contrast | Unverified | Check with Increase Contrast. |
| Reduced Motion | Likely | Check with Reduce Motion. |
| Differentiate Without Color Alone | Likely | Check conflict and error states. |
| Captions, Audio Descriptions | Not applicable | The app has no video or audio content. |

Declare nothing that hasn't been checked on the submitted build.

---
id: settings-about
title: Settings ▸ About, and the Help menu
features: [about-links, help-menu, rate-app]
sources:
  - apps/apple/JournalApp/Views/AboutLinks.swift
  - apps/apple/JournalApp/AppCommands.swift
  - docs/design/about-and-ratings-2026-10-05.md
---

# Settings ▸ About, and the Help menu

## Purpose

Links that leave the app (the privacy policy, support, the source code, the user guide, and the store's review page) and the app's version.

## Entry points

- Phone and tablet: the About section of Settings, after the six pane rows (`screens/settings`).
- Computer, and a tablet with a menu bar or keyboard: the Help menu.

## Content

### Settings ▸ About (phone and tablet)

A section with header `settings.about.header`, containing four link rows, in this order:

1. `common.privacyPolicy` → the privacy policy page.
2. `settings.about.support` → the support page.
3. `settings.about.sourceCode` → the source repository.
4. `common.rateMyJournal` → the app store's write-a-review page for My Journal.

Footer: the version, `settings.about.version` ("Version {version} ({build})"), selectable. Without a build number it reads `settings.about.versionWithoutBuild`.

### Help menu (computer, tablet with menu bar)

The Help menu replaces the system's help items with, in this order:

1. `library.menu.help.guide` ("My Journal Help"), shortcut Command-? → the user guide.
2. Separator.
3. `library.menu.help.support` ("My Journal Support") → the support page.
4. `common.privacyPolicy` → the privacy policy page.
5. `library.menu.help.source` ("Source Code on GitHub") → the source repository.
6. Separator.
7. `common.rateMyJournal` → the app store's write-a-review page.

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Privacy Policy | `about-privacy-policy` | Opens `PRIVACY.md` in the repository in the browser. |
| Support | `about-support` | Opens `SUPPORT.md` in the repository. |
| Source Code | `about-source-code` | Opens the repository's home page. |
| Rate My Journal | `about-rate` | Opens the app store's review page for My Journal, ready to write a review. On the Mac, opens the Mac App Store app directly rather than a web page. |
| My Journal Help | `help-guide` | Opens the user guide (`docs/guide/README.md`). |

## Rules

- Addresses, as the store listing uses them:
  - Repository: the project's public GitHub repository (the address is a constant in the app, `AboutLinks.swift`)
  - User guide: `<repository>/blob/main/docs/guide/README.md`
  - Support: `<repository>/blob/main/SUPPORT.md`
  - Privacy policy: `<repository>/blob/main/PRIVACY.md`
  - Review page (Apple): `https://apps.apple.com/app/id6816758959?action=write-review`; the Mac uses the `macappstore://` scheme for the same address. Windows and Android use their own store's review page.
- Rate My Journal always opens the store page. It is never the system's in-app rating prompt, which follows its own rules (`flows/rating-request`).
- The version shown is the marketing version and the build number, as the platform reports them.
- There is no help book; all help is on the web.

## Accessibility

- The version is read as `settings.about.version.spoken` ("Version {version}, build {build}"), so "1.0 (17)" isn't read as punctuation.
- Link rows are announced as links.

## Platform notes (Apple)

- iPhone and iPad show About in Settings; the Mac doesn't, because the Help menu holds the same links and the Mac's About My Journal window shows the version.
- On iPad with a hardware keyboard or menu bar, the Help menu is also available.
- The Help menu items name the app ("My Journal Help", "My Journal Support") because, unlike the Settings rows, they're read without a section header.

## Open questions

- None.

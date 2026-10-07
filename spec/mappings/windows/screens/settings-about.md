---
id: settings-about
title: Settings ▸ About and the Help menu (Windows)
spec: screens/settings-about.md
features: [about-links, help-menu, rate-app]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/uwp/launch-resume/launch-store-app
  - https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-default-app
---

# Settings ▸ About and the Help menu (Windows)

The links that leave the app, the version, and the Help menu. Behaviour and copy keys are the spec's [About and Help](../../../screens/settings-about.md); the shell and patterns are in [settings](settings.md#card-patterns). Windows shows About on the Settings home page (Windows apps keep About in Settings, [platform.md, 10](../platform.md#10-settings)) and in the Help menu ([platform.md, 4.1](../platform.md#41-where-the-menu-bar-sits)).

## Controls

### About group on the Settings home page

Header `settings.about.header`, after the six pane cards. Four [link cards](settings.md#card-patterns) in the spec's order, each opening the address in the default browser with `Launcher.LaunchUriAsync`, `Header` the label, `ActionIcon` the external-link glyph, `AutomationProperties.LocalizedControlType` "link":

1. `common.privacyPolicy`
2. `settings.about.support`
3. `settings.about.sourceCode`
4. `common.rateMyJournal`, only in a Microsoft Store build (`Package.Current.SignatureKind` is Store); icon Favorite (E734). It opens the Store review page for the app (`ms-windows-store://review/?ProductId=` and the product ID, a constant of the app); where the Store app is missing, nothing opens and nothing is said (the Store link is a system handler). It is never the in-app rating prompt ([platform.md, 28](../platform.md#28-rating)).

Below the group, `Caption` text with `IsTextSelectionEnabled`: `settings.about.version` ("Version {version} ({build})"), or `settings.about.versionWithoutBuild` when there is no build number. The version is the marketing version and the build number from the package version `Major.Minor.Build.0` (version = Major.Minor, build = Build); an unpackaged development build uses the assembly's version and shows no build. Addresses are the spec's (repository, `blob/main/docs/guide/README.md`, `SUPPORT.md`, `PRIVACY.md`); there is no help file.

### Help menu

| Item | Control | Notes |
| --- | --- | --- |
| `library.menu.help.guide` | `MenuFlyoutItem`, shortcut F1 | Opens the user guide |
| `library.menu.help.support`, `common.privacyPolicy`, `library.menu.help.source` | `MenuFlyoutItem`s | The two Settings rows and the Help items name the app because the Help items are read without a header |
| separator | | |
| `common.rateMyJournal` | `MenuFlyoutItem`, Store builds only | As above |
| separator, then "About My Journal" | `MenuFlyoutItem` | Opens Settings, scrolls the About group into view and moves focus to its first link. System item (command `about`) |

In the small layout the Help menu is a sub-menu of the single More menu ([platform.md, 4.1](../platform.md#41-where-the-menu-bar-sits)).

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | The group in the column; link cards full width | iPhone and iPad About section |
| Small and text size 200% or more | The same; the version wraps | iPhone |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `about-privacy-policy`, `help-privacy` | About card; Help menu | as in commands.md | Always |
| `about-support`, `help-support` | About card; Help menu | as in commands.md | Always |
| `about-source-code`, `help-source` | About card; Help menu | as in commands.md | Always |
| `about-rate`, `help-rate` | About card; Help menu | as in commands.md | Store builds only |
| `help-guide` | Help menu | `F1` | Always |
| `about` | Help menu | — | Always |

## Copy differences

Sentence case applies ("Privacy policy", "Support", "Source code", "Rate My Journal", "My Journal Help"). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `library.menu.help.source` | Source Code on GitHub | Source code on GitHub | casing (GitHub stays) |

## Accessibility

- Link cards are announced as links, with the destination host in their `HelpText` ("Opens in your browser" is not added: it would be new copy).
- The version is read as `settings.about.version.spoken` ("Version {version}, build {build}") through `AutomationProperties.Name`, so "1.0 (17)" is not read as punctuation.
- Focus after About My Journal is on the first link; Back returns to where the command was used.

## Different by design

- **About on the home page and in Help.** The Mac has it only in the Help menu and its About window; the phone only in Settings. Windows has both because both are Windows conventions.
- **Rate only from the Store.** Apple always has an App Store page. A direct-download build has no Store page, so the item is absent there ([platform.md, 18](../platform.md#18-packaging-distribution-and-updates)).

## Open questions

None.

# Public website — design

2026-09-27. Scope: the small static website at https://ralphkrauss.github.io/my-journal/ (home, privacy policy, support, not-found page), served by GitHub Pages from `website/` through `.github/workflows/pages.yml`. The privacy and support pages are the App Store privacy policy and support URLs.

This record was revised after its independent review ([website-review.md](website-review.md)). The pages in `website/` hold the exact copy; this record describes the structure, the visual rules and the decisions behind them.

## Requirements

- Calm, clean and simple, as if Apple made it; match the app icon (a handwritten deep-navy "My" on a warm paper-white gradient).
- Static HTML and CSS only: no JavaScript, web fonts, trackers, analytics, cookies or third-party requests. System font stack.
- Responsive from phone to desktop: 16 px side gutters, no horizontal scrolling. Light and dark appearance through `prefers-color-scheme`. WCAG AA contrast, landmarks, a skip link, alt text, visible keyboard focus.
- Copy follows AGENTS.md: plain, concise, no marketing language, no exclamation marks. Every claim is true of the current code and documents.
- The privacy policy is accurate to SECURITY.md, docs/architecture.md, the protocol and the privacy manifest.

## Structure shared by all pages

- A skip link, "Skip to main content", shown only when focused; it moves focus to `<main tabindex="-1">`.
- Header: a home link with the icon (28 px, `alt=""` because the name follows) and "My Journal", and a site navigation list with Privacy and Support. The current page's link is bold and underlined and has `aria-current="page"`. The header wraps below the name when space runs out (320 px at 200% text).
- Footer: a navigation list (Privacy, Support, Source code), "© 2026 Ralph Krauss. My Journal is open source under the Apache License 2.0." and Apple's trademark credit line.
- Every page has a meta description, `color-scheme`, `theme-color` for both appearances, a canonical URL, a Content-Security-Policy meta tag that allows only same-origin images and styles, and `referrer: no-referrer`. The home page has Open Graph tags for link previews.
- `404.html` uses absolute `/my-journal/` paths because GitHub Pages serves it for any missing path.

## Visual design

- One stylesheet. System fonts; body 17 px in `rem` so browser text size applies, and on iPhone and iPad the root follows the system Text Size setting (`-apple-system-body`). Text measures are in `rem`.
- Light: paper gradient #FFFDF9 → #F7F0E6; text #1B2233; headings #172A5C (the icon's navy); secondary #545B6B; links #1D4DB0; solid white cards with a navy hairline.
- Dark: deep navy #0E1528 → #121B32; text #EEE8DE; headings #FAF6EF; secondary #AEB4C2; links #A9C1FF; solid #182139 cards with a paper-coloured hairline.
- All text pairs pass AA; most pass AAA (see the review for ratios). Links in content are always underlined; links differ from body text by more than colour. Increased contrast turns secondary text and hairlines to the text colour and underlines navigation links. Forced colours use system colours for card borders.
- Focus: a 3 px outline in the link colour, 2 px offset, on `:focus-visible`.
- No animation, translucency or blur. Print hides navigation and the contents list and uses black on white.
- The icon is shown with a 22.4% corner radius and a 1 px edge so the paper-white artwork doesn't disappear into the page. The hero icon is 128 px (112 px on phones) with 256 px and 384 px sources.

## Home page

Icon, "My Journal", the lead "A private, encrypted journal for iPhone, iPad and Mac that works offline and needs no account.", availability as plain text ("Coming soon to the App Store. One purchase for iPhone, iPad and Mac." and the system requirements; no badge or pill, because Apple's badge is only for available apps and a pill looks like a button), six feature cards (Writing, Separate journals, Sync with your own server, End-to-end encryption, App Lock and backups, Agent access on the Mac) and "Free to build from source" with a link to the repository.

## Privacy policy

First person, since one person makes the app. "In short" summary, an "On this page" list, then short sections: On your devices, Sync with your own server (including the full list of what the server can see, matching SECURITY.md), Adding a device, Images and camera, Archives, Agent access on the Mac, Apple (App Store, analytics sharing, TestFlight), This website, Support requests, Keeping and deleting your data (retention, Delete Permanently limits, removing a device, the server and agent access), Children, Changes to this policy, Contact. Effective date September 27, 2026.

## Support page

A privacy warning before any action, then: Ask a question (email; no GitHub account needed), Report a problem or suggest an improvement (GitHub issues, what to include), Report a security problem (private vulnerability reporting), Keep your master password safe, Documentation (self-hosting, security model, all documentation, changelog).

## States

The site is static: there are no loading, empty or error states. Offline, the browser shows its own page. Missing paths show the site's not-found page.

## Images

The icon files are scaled from the chosen icon artwork (`app-icon-256.png`, `app-icon-384.png`, `apple-touch-icon.png` at 180 px, `favicon.png` at 64 px). If the final icon assets change, only these files are replaced.

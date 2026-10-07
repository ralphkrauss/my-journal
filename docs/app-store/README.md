# App Store material

What to enter in App Store Connect for My Journal (bundle ID `io.github.ralphkrauss.myjournal`, one free universal app for iPhone, iPad and Mac), ready to paste. Updated on 2026-10-05 for version 1.0, build 16, against the code and Apple's current documentation; each file links its sources.

Start with [launch-checklist.md](launch-checklist.md): it lists every step in order, every App Store Connect field with its value, and what only the owner can do.

| File | Contents |
| --- | --- |
| [launch-checklist.md](launch-checklist.md) | The ordered launch checklist: open findings, agreements, the app record, every field by its App Store Connect label, screenshots, builds and the final check |
| [listing.md](listing.md) | The audience and the who-it's-for statement; name, subtitle, categories, promotional text, descriptions for iOS and Mac, keywords for English (U.S.) and (U.K.), URLs, copyright, What's New, the counts, and the claims checked against the build |
| [app-privacy.md](app-privacy.md) | App Privacy answers (Data Not Collected), every network connection in the code, and the privacy manifest |
| [age-rating.md](age-rating.md) | Age rating questionnaire answers (4+) |
| [export-compliance.md](export-compliance.md) | Encryption export compliance: why `ITSAppUsesNonExemptEncryption` stays NO, the answers to give, U.S. and French rules |
| [review-notes.md](review-notes.md) | App Review notes for iOS and Mac, the optional demo server, owner to-dos |
| [screenshots-plan.md](screenshots-plan.md) | Screenshot sizes, the six frames per platform, sample content, the build 16 recapture (outdated frames, script changes, captures to run), composition specs, App Preview storyboard |
| [screenshots/](screenshots/) | The screenshots to upload: `iphone/` (6.9", 1320 × 2868), `ipad/` (13", 2752 × 2064), `mac/` (2880 × 1800). The current set dates from 2026-09-28 and must be recaptured for build 16 |

When the app, the privacy policy or the privacy manifest changes, check these files again. The URLs and signing steps are in [release operations](../release-operations.md#app-store-connect).

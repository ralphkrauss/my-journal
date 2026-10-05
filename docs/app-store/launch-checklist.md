# Launch checklist

Everything needed to publish My Journal 1.0 (build 16) in the App Store for iPhone, iPad and Mac, in order. Written on 2026-10-05.

Each item is marked:

- **Done** with its evidence.
- **Prepared, owner action:** the material is ready; only the owner can do it, or it needs an owner decision.
- **Claude can do with permission:** an agent can enter or check it in App Store Connect after the owner signs in and approves.

App Store Connect labels are written as they appear on screen as of October 2026. If a label differs, use the one on screen and tell the person who wrote this list.

## 0. Before App Store Connect: open findings for build 16

Found while preparing this kit. The first two could lead to a rejected upload or review; the owner chose to fix 0.1 to 0.4 in build 17 (2026-10-05).

| # | Finding | Recommendation | Status |
| --- | --- | --- | --- |
| 0.1 | **Privacy manifest is incomplete.** The iOS app uses two required-reason APIs that `PrivacyInfo.xcprivacy` doesn't declare: file timestamps (`contentModificationDate` in `ServerJoining.swift`) and disk space (`volumeAvailableCapacityForImportantUsage` in `EncryptionOperations.swift`). Apple says uploads without these declarations aren't accepted (ITMS-91053); the rule covers iOS, not macOS. Builds up to 16 were accepted by TestFlight, so check the upload emails. | Add `NSPrivacyAccessedAPICategoryFileTimestamp` with `C617.1` and `NSPrivacyAccessedAPICategoryDiskSpace` with `E174.1` ([app-privacy.md](app-privacy.md#privacy-manifest)), in build 17. | Done in build 17: the app declares `C617.1`, `E174.1` and `85F4.1` besides `CA92.1`. The server's own manifest went away when the server was removed from the Mac app (2026-10-05), so the app's manifest is the only one. Audit and reasons in [app-privacy.md](app-privacy.md#privacy-manifest). |
| 0.2 | **No privacy policy link inside the app.** Guideline [5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) asks for the link in App Store Connect *and* within the app. The app has none (the Mac Help menu is empty, and iOS Settings has no About or Privacy Policy row). | Add a Privacy Policy link, for example at the end of Settings > Privacy on iPhone and iPad and in the Mac's Help menu, through the design gate, in build 17. | Done in build 17: Settings > About on iPhone and iPad, and the Help menu on the Mac and iPad ([about-and-ratings-2026-10-05.md](../design/about-and-ratings-2026-10-05.md)). |
| 0.3 | **Use This Mac on Intel Macs.** The Mac app is universal, but its bundled server is built for Apple silicon only (`scripts/archive-mac.sh`). On an Intel Mac, Use This Mac… is offered and would fail with a generic error. | The Mac description now says "Using this Mac as a sync server requires a Mac with Apple silicon." Decide later between hiding or explaining the button on Intel Macs, shipping a universal server, or making the Mac app Apple silicon only. | Resolved by removing the server from the Mac app (2026-10-05, owner decision; [client-only-mac-lists-markdown-2026-10-05.md](../design/client-only-mac-lists-markdown-2026-10-05.md) §1). The app has no Apple-silicon-only part and runs fully on Intel Macs. Use This Mac… and the Intel message are gone, and the Mac description no longer mentions Apple silicon. |
| 0.4 | `ThirdPartyNotices.txt` (shown in the app) still mentions "the journal-agent helper", which was removed. | Change the sentence in build 17. Not a review risk. | Done in build 17. Since 2026-10-05 the notices are split: the apps carry `apps/apple/JournalApp/Resources/ThirdPartyNotices.txt` (not shown in the app), and the server package and container carry `packaging/server-THIRD-PARTY-NOTICES.txt`. |
| 0.5 | No Markdown export. Entries are stored as Markdown and visible in the source view, and the archive format is documented, but the app can't export Markdown files. | Add Export as Markdown in build 17. | Done in build 17: Settings > Backup > Export as Markdown… and File > Export Journals as Markdown… ([client-only-mac-lists-markdown-2026-10-05.md](../design/client-only-mac-lists-markdown-2026-10-05.md) §3, format in [protocol/markdown-export.md](../../protocol/markdown-export.md)). The descriptions, What's New and README now mention it. |

If the owner ships build 16 as is, 0.1 is the item most likely to block: check the App Store Connect email for build 16's iOS upload first.

## 1. Account and agreements (owner only)

| # | Item | Where | Status |
| --- | --- | --- | --- |
| 1.1 | Sign the **Paid Apps Agreement** (the Account Holder only). It must be Active before a paid app can be submitted. | App Store Connect > Business > Agreements | Prepared, owner action |
| 1.2 | **Tax forms** for the Paid Apps Agreement (outside the U.S., usually the U.S. W-8BEN form, plus any others App Store Connect asks for). | Business > Agreements > Tax Forms | Prepared, owner action |
| 1.3 | **Bank account** for payments. | Business > Agreements > Bank Accounts | Prepared, owner action |
| 1.4 | **EU Digital Services Act trader status.** Selling a paid app is likely trader activity; then the address, phone number and email entered are shown on the EU product page. Without a declaration the app isn't available in the EU. | Business > Digital Services Act (or App Information > Digital Services Act Compliance) | Prepared, owner action |
| 1.5 | Optional: enroll in the **App Store Small Business Program** for a 15% commission instead of 30% on paid apps, for developers under $1 million a year. Takes effect after approval. | developer.apple.com > Account | Prepared, owner action |

Sources: [Sign and update agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements), [DSA trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements).

## 2. The app record

One app record for iOS and macOS, so one purchase covers both (universal purchase).

| # | App Store Connect label | Value | Status |
| --- | --- | --- | --- |
| 2.1 | Apps > + > New App > **Platforms** | iOS and macOS (both checked) | Claude can do with permission |
| 2.2 | **Name** | `My Journal – Private Diary` (en dash) | Claude can do with permission |
| 2.3 | **Primary Language** | English (U.S.) | Claude can do with permission |
| 2.4 | **Bundle ID** | `io.github.ralphkrauss.myjournal` (one ID for iOS and macOS) | Claude can do with permission; the ID must already be registered with the team (it is, since TestFlight builds exist) |
| 2.5 | **SKU** | `myjournal` (internal, never shown; can't be changed later) | Claude can do with permission |
| 2.6 | **User Access** | Full Access | Claude can do with permission |

If the record already exists from TestFlight, check that both platforms are on it. A missing platform is added with **Add Platform** in the sidebar, using the same bundle ID ([Add platforms](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms)).

## 3. App Information (shared by iOS and macOS)

General > App Information. Text from [listing.md](listing.md).

| # | App Store Connect label | Value | Status |
| --- | --- | --- | --- |
| 3.1 | **Name** | `My Journal – Private Diary` | Claude can do with permission |
| 3.2 | **Subtitle** | `Simple, encrypted, and yours` | Claude can do with permission |
| 3.3 | **Category: Primary** | Lifestyle | Claude can do with permission |
| 3.4 | **Category: Secondary (optional)** | Productivity (recommended) or none | Prepared, owner action (decision) |
| 3.5 | **Content Rights** ("Does your app contain, show, or access third-party content?") | No | Claude can do with permission |
| 3.6 | **Age Rating** > Edit | Answers in [age-rating.md](age-rating.md); result 4+ | Claude can do with permission |
| 3.7 | **License Agreement** | Apple's Standard License Agreement (the Apache License covers the source code, not the App Store copy) | Claude can do with permission |
| 3.8 | **App Encryption Documentation** | None. `ITSAppUsesNonExemptEncryption` is NO; see [export-compliance.md](export-compliance.md) | Done (`apps/apple/project.yml`) |
| 3.9 | **Accessibility** (Accessibility Nutrition Labels, optional) | Declare only features checked on build 16; see [listing.md](listing.md#accessibility-nutrition-labels-optional). Leaving them empty is fine. | Prepared, owner action |

## 4. App Privacy

Trust & Safety > App Privacy (or General > App Privacy). Answers in [app-privacy.md](app-privacy.md).

| # | App Store Connect label | Value | Status |
| --- | --- | --- | --- |
| 4.1 | **Privacy Policy URL** | `https://github.com/ralphkrauss/my-journal/blob/main/PRIVACY.md` (HTTP 200 on 2026-10-05) | Claude can do with permission |
| 4.2 | **User Privacy Choices URL** (optional) | Empty | Claude can do with permission |
| 4.3 | **Data Collection** > Get Started > "Do you or your third-party partners collect data from this app?" | No, we do not collect data from this app | Claude can do with permission |
| 4.4 | **Publish** | Publishes "Data Not Collected" | Claude can do with permission |

## 5. Pricing and Availability

Monetization > Pricing and Availability. Prices are set once for the app; universal purchase covers both platforms.

| # | App Store Connect label | Value | Status |
| --- | --- | --- | --- |
| 5.1 | **Price Schedule** > Add Pricing > **Base Country or Region** | The owner's home storefront (prices in its currency, other regions derived) or United States; owner's choice | Prepared, owner action (decision) |
| 5.2 | **Price** | Owner decision; see the options below | Prepared, owner action (decision) |
| 5.3 | **App Availability** | All countries and regions, except China mainland (needs an ICP filing number) | Prepared, owner action (decision) |
| 5.4 | **Pre-Orders** | Off | Claude can do with permission |
| 5.5 | **iPhone and iPad Apps on Apple Silicon Macs** | Off: the Mac app is the Mac version | Prepared, owner action (decision) |
| 5.6 | **Apple Vision Pro** ("Make this app available") | Off unless tested on visionOS | Prepared, owner action (decision) |

Price options (one-time, U.S. price points; the App Store shows local prices elsewhere):

| Price | For | Against |
| --- | --- | --- |
| $4.99 | Low barrier for a first purchase; easy to try | Little room for a later launch discount; funds less development |
| $9.99 | A common price for a complete one-time app on three platforms; still an easy decision | |
| $14.99 to $19.99 | Signals a lasting tool bought once instead of a recurring cost | Fewer impulse purchases from people who don't know the project yet |

A launch price that later rises is possible (Price Schedule allows dated changes). Free with a paid upgrade isn't an option without in-app purchases, which the owner ruled out.

Sources: [Set a price](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price).

## 6. iOS version 1.0

iOS App > 1.0 Prepare for Submission. Text from [listing.md](listing.md#iphone-and-ipad-ios-platform-version).

| # | App Store Connect label | Value | Status |
| --- | --- | --- | --- |
| 6.1 | **Previews and Screenshots** > iPhone 6.9" Display | Six frames from `docs/app-store/screenshots/iphone/` (1320 × 2868), uploaded in the order in [screenshots-plan.md](screenshots-plan.md#the-story): 01, 03, 06, 02, 04, 05. After the recapture in [screenshots-plan.md](screenshots-plan.md#recapture-for-build-16) | Prepared, owner action (current frames are outdated; recapture first) |
| 6.2 | **Previews and Screenshots** > iPad 13" Display | Six frames, `docs/app-store/screenshots/ipad/` (2752 × 2064), in the same order as iPhone | Same as 6.1 |
| 6.3 | **Promotional Text** | listing.md, 144 characters | Claude can do with permission |
| 6.4 | **Description** | listing.md, iOS description, 3529 characters | Claude can do with permission |
| 6.5 | **Keywords** | `markdown,self-hosted,open source,e2ee,privacy,secure,offline,local,notes,encryption,sync,foss,mcp` (97 bytes) | Claude can do with permission |
| 6.6 | **Support URL** | `https://github.com/ralphkrauss/my-journal/blob/main/SUPPORT.md` | Claude can do with permission |
| 6.7 | **Marketing URL** | `https://github.com/ralphkrauss/my-journal` | Claude can do with permission |
| 6.8 | **Version** | `1.0` (matches `MARKETING_VERSION`) | Done (`apps/apple/project.yml`) |
| 6.9 | **Copyright** | `2026 Ralph Krauss` | Claude can do with permission |
| 6.10 | **Build** > Add Build | Build 16 of 1.0 (iOS) | Prepared, owner action (confirm the build finished processing and has no export compliance warning) |
| 6.11 | **App Review Information** > Sign-In required | Off | Claude can do with permission |
| 6.12 | **App Review Information** > Contact Information | Ralph Krauss, ralph@krauss.be, phone in international format | Prepared, owner action (phone number) |
| 6.13 | **App Review Information** > Notes | [review-notes.md](review-notes.md#notes-for-iphone-and-ipad), 3190 bytes with placeholders | Prepared, owner action (demo server decision) |
| 6.14 | **App Review Information** > Attachment | Optional screen recording of Agent Access | Prepared, owner action |
| 6.15 | **App Store Version Release** | Manually release this version (recommended for the first release, so iOS and Mac go live together) | Prepared, owner action (decision) |
| 6.16 | What's New | Not shown for the first version | Done (not applicable) |
| 6.17 | Phased Release for Automatic Updates | Not available for the first version; consider it from 1.0.1 | Done (not applicable) |

The app icon isn't uploaded here: App Store Connect takes it from the build (`apps/apple/JournalApp/Resources/AppIcon.icon`, the navy "My" on warm paper). Done.

## 7. macOS version 1.0

macOS App > 1.0 Prepare for Submission. Text doesn't carry over from iOS; enter it again. Text from [listing.md](listing.md#mac-macos-platform-version).

| # | App Store Connect label | Value | Status |
| --- | --- | --- | --- |
| 7.1 | **Previews and Screenshots** > Mac | Six frames, `docs/app-store/screenshots/mac/` (2880 × 1800), uploaded in the order 01, 03, 06, 04-insights, 02, 05 | Prepared, owner action (recapture first; 04-insights must be replaced) |
| 7.2 | **Promotional Text** | Same as iOS | Claude can do with permission |
| 7.3 | **Description** | listing.md, Mac description, 3703 characters | Claude can do with permission |
| 7.4 | **Keywords** | Same as iOS | Claude can do with permission |
| 7.5 | **Support URL**, **Marketing URL**, **Copyright** | Same as iOS | Claude can do with permission |
| 7.6 | **Version** | `1.0` | Done |
| 7.7 | **Build** > Add Build | The submitted build of 1.0 (macOS), archived with `scripts/archive-mac.sh`, which removes resource bundle signatures App Store Connect rejects and checks the entitlements. Builds from 2026-10-05 on contain no server. | Prepared, owner action (confirm the Mac build was uploaded and processed) |
| 7.8 | **App Review Information** | As iOS, with the Mac notes from [review-notes.md](review-notes.md#notes-for-the-mac) (2949 bytes) | Prepared, owner action |
| 7.9 | **App Store Version Release** | Same choice as iOS | Prepared, owner action (decision) |

Mac App Store requirements:

- **App Sandbox:** required, and on. The app is sandboxed (`apps/apple/Signing/JournalMac.entitlements`; [mac-app-store-sandbox.md](../design/mac-app-store-sandbox.md)) and has no helper since the server was removed from it (2026-10-05). Done.
- **Notarization:** not needed for the Mac App Store ([Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)). Done (not applicable).
- **Guideline 2.4.5(iii):** the app starts no process that outlives it and nothing at login; the bundled server that needed this was removed on 2026-10-05 ([review-notes.md](review-notes.md#the-mac-apps-sandbox)). Done.

## 7a. English (U.K.) localization

In App Information and on each platform version, add **English (U.K.)** with the language pop-up menu at the top of the page (check the label on screen), then fill in the fields from [listing.md](listing.md#english-uk-localization): the same name, subtitle, promotional text and URLs; the descriptions with "ORGANISE"; and the U.K. keywords `zero-knowledge,end-to-end,local-first,plain text,vault,lock,password,server,agent,homelab,journaling` (100 bytes). Screenshots can use the English (U.S.) ones. Status: Claude can do with permission.

## 8. Export compliance

| # | Item | Status |
| --- | --- | --- |
| 8.1 | `ITSAppUsesNonExemptEncryption = false` for iOS and macOS; if asked, "None of the algorithms mentioned above" | Done ([export-compliance.md](export-compliance.md)); owner confirms the answer |
| 8.2 | No CCATS, no French declaration, no BIS report or open-source notification needed with the operating system's encryption only | Done ([export-compliance.md](export-compliance.md)) |

## 9. Website and repository

| # | Item | Status |
| --- | --- | --- |
| 9.1 | README.md, PRIVACY.md, SUPPORT.md and the user guide describe build 16 | Done (2026-10-05 update) |
| 9.2 | The support, marketing and privacy URLs answer without signing in | Done (HTTP 200 on 2026-10-05) |
| 9.3 | Private vulnerability reporting is on | Done (owner, 2026-09-27) |
| 9.4 | After approval: add the App Store link to README.md ("Get My Journal") and to `docs/guide/getting-started.md`, set the repository's Website field ([github-metadata.md](../github-metadata.md)), and add a 1.0 section to CHANGELOG.md | Claude can do with permission, after release |

## 10. Final check before Submit for Review

- [ ] Paid Apps Agreement Active; tax and banking complete; trader status declared.
- [ ] Build 17 decision made for items 0.1 to 0.4; if a new build, its number selected on both platforms and the claims in listing.md rechecked.
- [ ] Screenshots recaptured, reviewed and uploaded for iPhone 6.9", iPad 13" and Mac; none shows a PIN, round checkboxes, Add Access… or private details.
- [ ] Every field in sections 3 to 7 filled; counts unchanged or recounted ([listing.md](listing.md#limits-and-counts)).
- [ ] Age rating shows 4+; App Privacy shows Data Not Collected and is published.
- [ ] Review notes: phone number filled, demo server block filled in or deleted, under 4000 bytes.
- [ ] Price and availability set; both platforms in the same release choice.
- [ ] Read the product page preview for each platform once, as a customer would.
- [ ] **Submit for Review** on both versions. Only the owner presses it. Claude doesn't submit.

## Owner-only actions

- Sign the Paid Apps Agreement, and enter tax, banking and trader details.
- Decide the price, availability, secondary category, release option and build 17.
- Enter the review contact phone number, and decide on the demo server.
- Press **Submit for Review**, and later **Release This Version** if releasing manually.

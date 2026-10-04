# Age rating answers

Answers for App Store Connect > App Information > Age Rating. The rating is set once for the app and applies to iPhone, iPad and Mac ([App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)). Checked 2026-09-28.

**Result: 4+.** Nothing in the app requires a higher rating.

## The questionnaire

Apple's current questionnaire (updated July 2025, with social media questions added in July 2026 that must be answered from September 2026) asks about in-app controls, capabilities, mature themes, medical or wellness topics, sexuality or nudity, violence and chance-based activities, then shows the calculated rating ([Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating), [Updated age ratings in App Store Connect](https://developer.apple.com/news/?id=ks775ehf)). The definitions below are Apple's ([Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)). The order of the steps in App Store Connect may differ; answer by name.

What the app ships with: no content of its own (new libraries start without templates since 2026-10-04), and no built-in AI. Everything else is what the person writes, for themselves.

### In-app controls

| Item | Answer | Why |
| --- | --- | --- |
| Parental Controls | No | No tools to restrict content for children. App Lock hides the app from other people; it isn't a parental control. |
| Age Assurance | No | The app doesn't check age. |

### Capabilities

| Item | Answer | Why |
| --- | --- | --- |
| Unrestricted Web Access | No | Defined as navigating to any webpage within the app, such as an embedded browser. The app has no web view or browser. A link in an entry opens in the person's default browser only when they choose it, and images linked from the web aren't loaded. |
| User-Generated Content | No | Defined as "broad distribution" of content created by users. Entries are private: they stay on the person's devices and their own server, and nobody else can see them. |
| Social Media | No | No feed, discovery, likes, comments or sharing between people. |
| Messaging and Chat | No | People can't communicate with each other through the app. Sync connects one person's own devices; agent access is one person's own agent reading their journals. |
| Advertising | No | No ads. |

Connecting to a server the person specifies doesn't match any capability: it syncs only that person's own journals.

### Mature themes

| Item | Answer |
| --- | --- |
| Profanity or Crude Humor | None |
| Horror/Fear Themes | None |
| Alcohol, Tobacco, or Drug Use or References | None |

The app contains none of these. What a person writes in their own journal isn't app content shown to others.

### Medical or wellness

| Item | Answer | Why |
| --- | --- | --- |
| Medical or Treatment Information | None | No diagnoses or treatment guidance. |
| Health or Wellness Topics | None | Defined as self-care or lifestyle recommendations, such as calorie tracking, dieting or exercise advice. The app includes no templates or prompts and makes no recommendations; templates are only what the person saves. |

### Sexuality or nudity

| Item | Answer |
| --- | --- |
| Mature or Suggestive Themes | None |
| Sexual Content or Nudity | None |
| Graphic Sexual Content and Nudity | None |

### Violence

| Item | Answer |
| --- | --- |
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Guns or Other Weapons | None |

### Chance-based activities

| Item | Answer |
| --- | --- |
| Simulated Gambling | None |
| Contests | None |
| Gambling | No |
| Loot Boxes | No |

### Additional information

| Item | Answer |
| --- | --- |
| Calculated rating | 4+ |
| Override to a higher rating | No |
| Age Suitability URL | Leave empty |
| Made for Kids | No. The app isn't designed for children, and the Kids category has its own requirements. |

Regional ratings (Australia, Brazil, Republic of Korea) are derived from these answers. With no social media, loot boxes or mature content, they stay at their lowest levels.

## Metadata

Screenshots and previews must suit a 4+ audience regardless of the rating (guideline [2.3.8](https://developer.apple.com/app-store/review/guidelines/)). The sample entries in [screenshots-plan.md](screenshots-plan.md) are written for that.

## When to answer again

Before adding an in-app browser or web view, sharing or publishing entries to other people, comments or collaboration, a built-in AI feature, or bundled content such as prompts that give health advice.

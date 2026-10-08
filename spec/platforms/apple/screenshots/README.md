# Apple screenshots

Captures of the Apple apps, one file per page state and device, for readers who cannot run the apps. They are produced by script from the seeded sample library, never by hand ([platforms/README.md](../../README.md), Screenshots).

## Layout and names

```text
screenshots/
  iphone/<id>-<state>.png
  ipad/<id>-<state>.png
  mac/<id>-<state>.png
```

- `<id>` is the id of the spec page the file belongs to; the page's front matter lists the file under `screenshots:`.
- `<state>` says what is shown, in lower-case kebab-case: `default`, `empty`, `loading`, `offline`, `error`, `locked`, `selected`, a named step of a flow (step-2), and the modifiers dark and large-text added after the state with a hyphen (default-dark, error-large-text). A screen and a flow with the same id share the folder, so give their states different names.
- PNG, no alpha. Fixed size per device so that two captures can be compared: iPhone portrait, iPad landscape, Mac window only (not the desktop). Light appearance unless the state says `dark`.
- Sample data only: the library seeded by `design/app-store/seed-library.sh`. A capture that shows anything personal is deleted and regenerated.

The checker validates these names, that every file a page lists exists, and warns about files no page lists.

## Regenerating

`mise exec -- design/spec-screenshots/capture.sh [iphone] [ipad] [mac]` regenerates every file from the sample library, with fixed dates and no personal data ([design/spec-screenshots/README.md](../../../../design/spec-screenshots/README.md)). Sizes: iPhone 17 simulator 603 x 1311 px; iPad Pro 11-inch (M5) simulator in landscape 1210 x 834 px; the Mac journal window 1280 x 800 px and its Settings window 560 px wide (one pixel per point). All are half of native size, PNG, at most 256 colours. A state that cannot be captured is explained in the page's Screenshots section.

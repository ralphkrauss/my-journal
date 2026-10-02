# Repository setup

These steps activate the GitHub protections prepared in `.github/`. Order matters: the branch ruleset requires status checks with no bypass, so a commit pushed directly to the default branch is refused until its checks have passed. If the ruleset is active before the first push, the first commit cannot be published.

1. **Push first.** Push the initial commit to `main` while no ruleset is active.
2. **Turn on private vulnerability reporting** in Settings > Code security. The issue forms send security reports to the repository's Security tab, which needs this setting.
3. **Import the rulesets** in Settings > Rules > Rulesets > New ruleset > Import a ruleset:
   - `.github/rulesets/releases.json` protects `v*` tags from being moved or deleted. It can be active immediately.
   - `.github/rulesets/quality.json` protects the default branch from deletion and force pushes and lists the required checks. Import it with enforcement set to **Disabled** until step 4.
4. **Enable required checks after the first CI run.** Wait for the Quality and Dependency Audit workflows to finish on `main`. Compare the check names shown on that commit with the ruleset (Hygiene, Backend, Apple, Integration, iOS UI, iOS Accessibility, Dependency Audit), correct any difference in the ruleset, then set its enforcement to **Active**.
5. **Work through branches from then on.** With required checks active, every change to `main` goes through a pull request whose checks have passed. If you want an emergency route, add the repository admin role as a bypass actor limited to pull requests; the prepared ruleset has none.
6. **Prepare releases** only when you are ready to publish or upload: create the protected environments `release-publish` (tags matching `v*`) and `testflight` (the `main` branch), each with the maintainer as required reviewer, before adding their secrets, as described in [release operations](release-operations.md).

Dependabot starts proposing updates after the first push; its configuration is in `.github/dependabot.yml`.

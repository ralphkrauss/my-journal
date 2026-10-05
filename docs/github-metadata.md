# GitHub repository settings

GitHub is the project’s only website, so the repository’s settings matter for how people find it. These aren’t stored in files; apply them on GitHub under the repository’s About panel (the gear next to About) and Settings > Private, end-to-end encrypted journal and diary app for Mac, iPhone and iPad. No account, no subscription, no company server: sync through your own server, or not at all. Markdown entries, checklists, photos, pinned entries, App Lock, and read-only MCP access for your own AI agent. Open source, with a self-hosted ASP.NET Core server for Docker.

## Description

346 characters; the limit is 350.

> Private, end-to-end encrypted journal and diary app for Mac, iPhone and iPad, with optional self-hosted sync. No account, no company server. Native SwiftUI apps, Markdown entries, templates, images, version history, App Lock, and read-only MCP access for your own AI agent. Self-hosted ASP.NET Core server with Docker and Tailscale.

Update it when the apps reach the App Store or new platforms arrive.

## Website

Leave empty until the App Store listing is live, then use the App Store link.

## Topics

GitHub allows up to 20. These use the spellings people already search for and follow:

```
journal
diary
journaling
journal-app
diary-app
privacy
end-to-end-encryption
encryption
self-hosted
selfhosted
local-first
swiftui
ios
macos
ipados
markdown
aspnet-core
docker
tailscale
mcp
```

Alternatives if one of these stops fitting: `e2ee`, `sqlite`, `dotnet`, `day-one-alternative`, `privacy-first`.

## Social preview

Settings > General > Social preview sets the image shown when the repository link is shared. GitHub recommends 1280 × 640 pixels (at least 640 × 320), PNG or JPEG, under 1 MB. Without one, GitHub shows a generated card with the owner’s avatar.

No image of that size exists yet. The simplest source is `docs/app-store/screenshots/mac/01-hero.jpg` (2880 × 1800): it already has the icon, the headline “A calm place to write” and the Mac window on the icon’s paper background. Crop it to 2:1 from the top (2880 × 1440) and scale it to 1280 × 640, or render a dedicated frame with `design/app-store/make_screenshots.py` using the same colors and type, with “My Journal” and “Private, encrypted, self-hosted” as the text. Keep the text large enough to read at small sizes, and use an opaque background, since the card appears on both light and dark pages.

## Other settings

- **Features:** keep Issues on, since support goes through them. Turn off Wiki and Projects unless you use them, so visitors aren’t sent to empty pages.
- **Releases:** publish the first release with notes from [CHANGELOG.md](../CHANGELOG.md). The release and the container package show in the sidebar and signal an active project.
- **Pin** the repository on your GitHub profile.

## Lists and directories

[awesome-selfhosted](https://github.com/awesome-selfhosted/awesome-selfhosted-data/blob/master/CONTRIBUTING.md) accepts projects whose first release is more than four months old, so submit it yourself once that’s true. It doesn’t accept machine-generated submissions.

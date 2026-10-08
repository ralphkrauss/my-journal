# Documentation

## Using My Journal

- [User guide](guide/README.md): getting started, sync, devices, backups, App Lock, agent access and troubleshooting.
- [Support](../SUPPORT.md) and [Privacy Policy](../PRIVACY.md).
- [Distribution and installation](distribution.md): channels, supported systems, setup choices and updates.
- [Self-hosting](self-hosting/README.md): run the server in a container, on a home server or a Mac, with Tailscale, or behind public HTTPS ([HTTPS example](self-hosting/https.md)).
- [Security model](../SECURITY.md): what is protected, what the server can see, and how to report a vulnerability.

## Working on the code

- [Architecture](architecture.md): components, data flow, storage, sync, encryption and agent access.
- [Development](development.md): building the apps and server, running checks and end-to-end tests.
- [Code hygiene](engineering/code-hygiene.md): the rules and tools the checks enforce.
- [Performance measurements](performance.md): opt-in resource probes and their latest results.
- [Protocol](../protocol/README.md): the versioned contracts shared by clients and the server.
- [Product spec](../spec/README.md): every screen, flow, message, command and string, independent of platform, with each platform's implementation notes and screenshots in [spec/platforms/](../spec/platforms/README.md). The spec is the starting point for porting a feature to another platform.
- [Design records](design/README.md): interface designs and their independent reviews, with the status of each.

## Maintaining the repository

- [Repository setup](repository-setup.md): the order for activating rulesets and required checks.
- [Release operations](release-operations.md): protected environments, signing and publishing a release.
- [App Store material](app-store/README.md): listing text, App Privacy and age rating answers, review notes and the screenshot plan.
- [GitHub repository settings](github-metadata.md): the description, topics and social preview to set on GitHub.

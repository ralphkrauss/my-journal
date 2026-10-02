# Server on this Mac — design revision 1

For independent review before UI implementation. The existing local-only app continues to work without running a server. A single macOS app download includes the optional self-contained ASP.NET server and the MCP helper; Docker/.NET are not required on that Mac. Separate Linux container deployments remain first-class.

## Setup choice

Settings > Sync > Server, when not connected, keeps “Your journals are saved on this device.” and offers “Use This Mac…” and “Connect to a Server…”. On iOS only the existing Connect action appears. A Mac user choosing Use This Mac sees a scrollable native sheet titled “Use This Mac as Your Server”, with text “Your journals will stay on this Mac. The server runs while Journal is open. To connect another device, keep this Mac awake and use a private connection such as Tailscale.” Explain “Your recovery key is needed to set up encrypted sync.” Secure Recovery Key field, Cancel and “Start Server”. If the existing recovery key has not yet been confirmed, finish the current recovery confirmation before allowing server setup.

If no journal exists yet, the welcome screen continues Start a Journal / Connect to a Server; local-server setup is available after the journal and recovery key exist. No third-party login or Docker prompt.

## Running and stopped states

After successful setup, Sync settings show “This Mac”, “Running”, and the existing Sync Now action. “Connection Details” disclosure shows local address and concise Tailscale instructions: use Tailscale Serve for the displayed local port, then connect other devices using its HTTPS address. Copy Address copies only the address, never credentials/setup code. Pairing stays in Devices. Do not imply that another device can reach127.0.0.1.

The server binds only a stable loopback port selected for this device, uses a private app-support data directory, and starts automatically when the app launches if previously enabled. It stops when the app quits, not when a single window closes. Agent-access last-window behavior is separate and unchanged. App lock does not stop encrypted backend sync for other devices.

“Stop Server” stops the child process without deleting data/configuration. Status becomes “Stopped”; action becomes “Start Server”. Explain “Other devices can sync when this server is running.” A stopped server should stay stopped across launches until restarted. Offline/local writing keeps working. No database/recovery-key paths in the normal writing UI.

If already connected to a separate server, show its address and existing controls; do not offer an implicit migration. Changing hosting while preserving server identity/data is a backup/restore workflow, not an automatic second server.

## Errors and lifecycle

Disable setup actions while starting and show “Starting Server…”. Cancel is disabled only for the short setup commit; lock cancels setup before a connection is committed. Port collision: “This server address is in use. Close the other app using it, then try again.” Missing bundled helper: “The server is missing from this copy of Journal. Reinstall Journal and try again.” Failed readiness/start: “Couldn’t start the server. Try again.” Wrong key restores focus with existing recovery-key wording. If server starts but initial sync fails, distinguish “Server running. Your journals are saved on this device and will sync when the connection is available.” Do not launch a second process on retry. If the server crashes, show Stopped/error with Start Server; no unbounded restart loop.

Data/configuration commits must precede success copy. Existing drafts flush before setup, recovery/PIN credentials are preserved, and a partially started server must be recoverable using the existing recovery key after app restart. Never overwrite a different service or delete a nonempty server directory on retry. Quit waits for pending local saves first, then requests graceful server termination. No root privileges or system-wide service installation.

## Accessibility and inspection

Native Form/DisclosureGroup, adaptive system colors/fonts, scrollable setup with persistent actions, selectable connection guidance, predictable recovery-field focus, keyboard/VoiceOver and visible status text. Review actual setup/error/running/stopped states after implementation. Distribution docs clearly distinguish local-only storage, server on this Mac and separate container hosting.

## Reviewed clarifications and platform support

The server runs until Journal quits, including when its last window closes. Local addresses are labeled Local Address; other devices need a private HTTPS address. Partial initialization preserves the server directory and resumes authorization with the recovery key. Cancel/lock before setup commit stops only the owned child and leaves its data for retry; after commit, lock leaves the encrypted backend running. Running requires the owned process plus readiness, and Stopped requires confirmed exit. Port conflicts never silently change a configured forwarded port.

The native client remains macOS13+. Microsoft’s .NET10 supported-OS matrix lists macOS14 as its minimum; Use This Mac therefore requires macOS14 and explains this on older systems. Local-only journaling and a separate server remain available on macOS13. Source: https://github.com/dotnet/core/blob/main/release-notes/10.0/supported-os.md (checked2026-09-20).

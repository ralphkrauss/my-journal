My Journal — development build

Drag My Journal.app to Applications. This is an ad-hoc signed development build for testing. Do not turn off Gatekeeper or other system protections to share it; the released app comes from the Mac App Store.

My Journal needs macOS 14 or later. It works on this Mac without a server, or connects to your own server. The bundled server includes its runtime, so no separate .NET or Docker installation is needed. To run it, open Settings > Sync and choose Use This Mac…. Keep My Journal running and this Mac awake while other devices sync. Connection Details explains how to give other devices a private HTTPS address with Tailscale. Stop Server pauses the server until you start it again; quitting My Journal stops it until the next launch.

Agents read the journals you choose through your sync server, including the one built into this app (Settings > Sync > Use This Mac…). See Settings > Agent Access. A cloud-based agent may send what it reads to its provider.

Save your master password in your password manager. Journals created with a recovery key keep using that key. Encryption is on by default; if you create your journals without encryption, anyone with access to the files, a server or a backup can read them. Back up before updating, and quit My Journal before replacing the app. Updating does not remove your journals in Application Support.

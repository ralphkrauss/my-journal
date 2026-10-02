# Sync

Sync keeps your journals the same on all your devices. It’s optional: without it, My Journal works fully on one device, offline.

There is no My Journal account or company server. Your devices sync through a server you run, and you choose where it runs.

## Choose where your server runs

| Option | What you need | Keep in mind |
| --- | --- | --- |
| [This Mac](#use-this-mac-as-your-server) | A Mac with macOS 14 or later, and [Tailscale](https://tailscale.com) on it and on your other devices | Other devices sync only while this Mac is awake and My Journal is open on it. |
| [Your own server with Tailscale](#use-your-own-server) | A home server or other computer that runs containers, and Tailscale | Available whenever that computer is on, and only your devices can reach it. |
| [A public HTTPS server](#use-your-own-server) | A host with a domain name | Reachable from anywhere. Anyone can try to guess your master password through it, so it must be long. |

Tailscale is a separate service that connects your devices privately. My Journal doesn’t require it, but it is the simplest way to reach a server without putting it on the public internet.

## Use this Mac as your server

1. On the Mac, choose Settings > Sync > **Use This Mac…**.
2. Enter your master password and choose **Start Server**.
3. To connect your other devices, install Tailscale on this Mac and on them. In Settings > Sync, open **Connection Details**, copy the `tailscale serve` command shown there and run it in Terminal. Tailscale then gives the server an HTTPS address ending in `.ts.net`.
4. [Add your other devices](devices.md#add-a-device). An iPhone or iPad scans a code; other devices use that HTTPS address.

The server runs while My Journal is open. It stops when you quit and starts again when you open My Journal, unless you chose **Stop Server**. Keep the Mac awake while your other devices need to sync.

## Use your own server

1. Set up the server by following [self-hosting](../self-hosting/README.md): a container on a home server, privately with Tailscale, or behind [public HTTPS](../self-hosting/https.md).
2. On the server, run `setup-code` to see its one-time setup code, for example `docker compose exec journal setup-code`. It looks like `K7Q-M4X`.
3. On your first device, choose **Connect to a Server…** (on the first screen, or in Settings > Sync). Choose your server under **Servers on This Network**, or enter its address and choose **Continue**. With Tailscale, use its HTTPS address while the device is connected to your tailnet.
4. Enter the **Setup Code** and choose **Continue**.
5. On a new device, choose whether to encrypt your journals under **Protect Your Journals**. With encryption, choose a master password and enter it again to verify it. On a device that already has journals, enter the master password you use for them; they're uploaded to the server. Choose **Set Up**.
6. When **Server Is Ready** appears, choose **Add Another Device…** or [add your other devices](devices.md#add-a-device) later. An iPhone or iPad only has to scan a code.

The setup code works once. After many wrong codes the server makes people wait longer between tries, so set it up before making it reachable beyond your tailnet or home network.

## How sync works

- My Journal syncs by itself every few seconds while it’s open and unlocked. To sync right away, choose **Sync Now** in Settings > Sync.
- Without a connection, keep writing. Your changes are saved on the device and sent when the connection returns. While changes are waiting or sync needs you, **Sync Status** explains why and offers the one action that helps, such as **Try Again** or **Connect Again…**: it’s a cloud button in the toolbar on the Mac, and in the entry’s … menu on iPhone and iPad. Settings > Sync shows the same, with **Last Synced** and how many items are **Not on Server Yet**. See [Sync isn’t working](troubleshooting.md#sync-isnt-working).
- To stop syncing a device, choose Settings > Sync > **Stop Syncing…**. Its journals stay on the device, including changes that weren’t sent, and it gives up its access to the server. To sync again later, choose **Connect to a Server…**; nothing is copied twice.
- If the same entry changes on two devices before they sync, both versions are kept for you to review. See [changes that need review](troubleshooting.md#an-entry-has-changes-from-another-device).
- Deleting and restoring sync too. Delete Permanently removes an item from your other devices when they sync, but your server keeps the earlier versions it received.

## What your server can see

With encryption on, your server stores your journals in a form it can’t read. It can’t see journal names, entry titles, entry dates, text, images, image descriptions or templates.

It, and anyone with its data or backups, can still see:

- how many journals, entries and templates you have;
- every version it received, kept permanently, with its size, when it arrived and which device sent it, which shows roughly how long your entries are and when you write;
- which items were probably deleted permanently, and each image’s size;
- your devices’ names (on a Mac, often including your name), and how and when each was added;
- network addresses, and when your devices connect.

Without encryption, anyone with access to the server or its backups can read everything. The [security model](../../SECURITY.md#what-the-server-can-see) has the full list.

Your master password never leaves your devices, but someone with the server’s data can try to guess it. Use a long, generated password, and prefer a server only your devices can reach, such as one on Tailscale.

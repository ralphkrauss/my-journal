# Sync

Sync keeps your journals the same on all your devices. It’s optional: without it, My Journal works fully on one device, offline.

There is no My Journal account or company server. To sync, you run a small server of your own, and each device connects to it. The server is also how an AI agent you choose can [read your journals](agent-access.md). With encryption on, it stores your journals in a form it can’t read.

## Choose where your server runs

The server runs on a computer you control that stays on while your devices sync, such as a home server, a NAS, a VPS, or a Mac or PC you leave on. The My Journal apps don’t run a server; they only connect to one.

| Option | What you need | Keep in mind |
| --- | --- | --- |
| [A server with Tailscale](../self-hosting/README.md#tailscale) | A computer that runs containers, such as a home server, a NAS or a Mac with Docker, and [Tailscale](https://tailscale.com) on it and on your devices | Available whenever that computer is on, and only your devices can reach it. |
| [A public HTTPS server](../self-hosting/https.md) | A host with a domain name | Reachable from anywhere. Anyone can try to guess your master password through it, so it must be long. |

Tailscale is a separate service that connects your devices privately. My Journal doesn’t require it, but it is the simplest way to reach a server without putting it on the public internet.

A Mac can be the server if it stays on and awake while your devices sync: run the container there with Docker Desktop or OrbStack. See [running the server on a Mac](../self-hosting/README.md#running-the-server-on-a-mac). [Self-hosting](../self-hosting/README.md) covers every setup, backups and updates.

## Use your own server

1. Set up the server by following [self-hosting](../self-hosting/README.md): a container on a home server or another computer, privately with Tailscale, or behind [public HTTPS](../self-hosting/https.md).
2. On the server, run `setup-code` to see its one-time setup code, for example `docker compose exec journal setup-code`. It looks like `K7Q-M4X`.
3. On your first device, choose **Connect to a Server…** (on the first screen, or in Settings > Sync). Choose your server under **Servers on This Network**, or enter its address and choose **Continue**. With Tailscale, use its HTTPS address while the device is connected to your tailnet.
4. Enter the **Setup Code** and choose **Continue**.
5. On a new device, choose whether to encrypt your journals under **Protect Your Journals**. With encryption, choose a master password and enter it again to verify it. On a device that already has journals, enter the master password you use for them; they're uploaded to the server. Choose **Set Up**.
6. When **Server Is Ready** appears, choose **Add Another Device…** or [add your other devices](devices.md#add-a-device) later. An iPhone or iPad only has to scan a code.

The setup code works once. After many wrong codes the server makes people wait longer between tries, so set it up before making it reachable beyond your tailnet or home network.

## If you used Use This Mac

Earlier test versions of My Journal for Mac could run a server inside the app, with **Use This Mac…**. The app no longer includes a server. A Mac that synced with it stopped syncing when the new version first opened, and Settings > Sync says so. Its journals stay on the Mac, including changes that weren’t sent. Other devices that synced through that Mac show that they can’t reach the server.

To sync again:

1. Set up a server elsewhere; see [Choose where your server runs](#choose-where-your-server-runs).
2. On the Mac, choose Settings > Sync > **Connect to a Server…** and connect to the new server. The Mac’s journals are uploaded to it.
3. On each other device, choose Settings > Sync > **Stop Syncing…**, then **Connect to a Server…** with the new server, and join it with the device’s journals. Changes that weren’t sent are kept, and nothing is overwritten.
4. On the Mac, turn off the old Tailscale Serve rule in Terminal: `tailscale serve --https=443 off`, or `tailscale serve reset` if it was the only rule.
5. [Connect your agents](agent-access.md#connect-an-agent) again. Their access belonged to the old server.

The Mac keeps the old server’s files, and Erase Journals and Settings doesn’t remove them. Instead of moving to a new server, you can also [keep using the old server’s data](troubleshooting.md#keep-using-the-old-servers-data) at the same address, so your other devices and agents keep working and only the Mac signs in again. To delete the files, see [Remove the old server’s files](troubleshooting.md#remove-the-old-servers-files).

## How sync works

- My Journal syncs by itself every few seconds while it’s open and unlocked. To sync right away, choose **Sync Now** in Settings > Sync.
- Without a connection, keep writing. Your changes are saved on the device and sent when the connection returns. While changes are waiting or sync needs you, **Sync Status** explains why and offers the one action that helps, such as **Try Again** or **Reconnect…**: it’s a cloud button in the toolbar on the Mac, and in the entry’s … menu on iPhone and iPad. Settings > Sync shows the same, with **Last Synced** and how many items are **Not on Server Yet**. See [Sync isn’t working](troubleshooting.md#sync-isnt-working).
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

# Troubleshooting

## I forgot my master password

Your master password can’t be recovered, and your server can’t reset it: it never receives the password.

- **You still have a device with your journals.** Keep using it; it opens without the password. If you sync, you can also add devices by [pairing](devices.md#add-a-device), which doesn’t need the password.
- **Your journals are only on this device.** The first time you choose Export Archive…, My Journal asks you to check your password. If you enter a wrong one, choose **Forgot Password?**. After you confirm it’s you with Face ID, Touch ID, or your passcode or Mac login password, you can set a new password. Archives you exported before still need the old one.
- **Otherwise,** you can’t open encrypted archives, recover your journals on a new device, or change the password without the current one.

Save your password in a password manager so this doesn’t happen again.

## I can’t unlock My Journal

App Lock uses your device’s Face ID, Touch ID or passcode, or your Mac login password; there’s no separate PIN. If your device can’t authenticate you, choose **Use Master Password** (or your recovery key) on the lock screen. If you removed your device’s passcode, My Journal turns App Lock off the next time it opens.

## An entry has changes from another device

When the same entry changes on two devices before they sync, My Journal keeps both versions instead of choosing one. The entry shows “This entry has changes from another device.” and is marked in the list. Settings > Sync lists every item under **Changes to Review**.

1. Choose **Review Changes**.
2. Switch between the versions from This Device and Other Device.
3. Choose **Keep Both** to save them as separate entries, or **Keep One Version** to keep only one.

The version you don’t keep stays in Version History. If an entry was deleted on one device and edited on another, you can keep the entry, keep it as a copy, or keep the deletion.

## Sync isn’t working

Your changes are always saved on the device first; sync never deletes them. **Sync Status** shows what’s wrong: the cloud button in the toolbar on the Mac, or the entry’s … menu on iPhone and iPad. Choose **Sync Settings…** there, or open Settings > Sync, to see the message, **Last Synced**, how many items are **Not on Server Yet**, and the one action that fixes it. The cloud shows an exclamation mark when you need to act, or when changes have waited more than a day.

- **“You’re offline.”**, **“Can’t reach the server right now.”** or **“The server isn’t available right now.”** My Journal tries again by itself, and as soon as the network returns. Check your connection and, if you use Tailscale, that it’s connected. If your Mac is the server, check that it’s awake and that Settings > Sync on the Mac says Running. **Try Again** syncs at once.
- **“The server isn’t set up.”** The server was reset and waits for a setup code. Choose **Set Up Server Again…** and enter the code your server shows (run `setup-code` on the server to see it again). This device’s journals become the server’s journals; your other devices then show “The server was restored or replaced…” and connect again without copying anything twice.
- **“The server was restored or replaced and doesn’t recognize this device.”** Choose **Connect Again…** and enter your master password, or use a connected device. If the server holds your journals, they continue where they left off. If it holds someone else’s library, **Merge Journals** asks before anything is sent.
- **“This device no longer has access to the server.”** The device was removed in Settings > Devices on another device. Choose **Connect Again…**.
- **“The server now uses encryption or was replaced. Sign in to keep syncing.”** Choose **Sign In…** and enter the master password your other devices use. Changes that hadn’t synced are kept.
- **“Update My Journal to sync with this server.”**, **“The server needs an update…”**, a certificate that isn’t valid, or an address that doesn’t lead to a My Journal server: fix the app or the server, then choose **Check Again**. My Journal also checks every few minutes.
- **“My Journal couldn’t read its data on this device.”** Your journals haven’t been changed. Export an archive in Settings > Backup to keep a copy, then quit and reopen My Journal.

**Your server moved to a new address.** Choose Settings > Sync > **Stop Syncing…**, then **Connect to a Server…** with the new address. Your journals stay on the device, and nothing is copied twice.

After a server is reset or restored, agents need access again in Settings > Agent Access.

## An entry or image is too large to sync

If an entry is too large for the server, My Journal says “… is too large to sync. It’s saved on this device.” Shorten it or split it into separate entries; it syncs once it’s small enough. The limit is about 4 MB of text, much longer than a typical entry.

If an image is too large (over about 25 MB), entries that include it stay on this device. Use a smaller copy of the image instead.

## What is Unavailable Journals?

Unavailable Journals appears in the sidebar when some entries can’t be shown in their journal: the journal hasn’t arrived on this device yet, it has changes to review, or it was saved by a newer version of My Journal. Your entries are still saved. Select an entry there to see why, and choose **Try Syncing Again** or **Review Changes** when offered.

## Move to a new device

- **If you sync:** [add the new device](devices.md#add-a-device). Your journals download to it.
- **If you don’t sync:** [export an archive](backups.md#export-an-archive) on the old device, copy the file to the new one, and choose **Import Archive…** on its first screen.

Then turn on App Lock and set up agent access again; they aren’t copied. Check that your journals arrived before you erase the old device, and [revoke its access](devices.md#remove-a-device).

## Delete your data

Nothing is deleted automatically.

- **Entries, journals and templates.** Deleting one moves it to Recently Deleted. There, choose **Delete Permanently…** to remove it and its earlier versions from this device, and from your other devices when they sync. Copies may remain in archives, backups and your server’s history, and images stay in the app’s storage.
- **Everything on a device.** If you sync, first choose Settings > Devices on another device and **Revoke Access…** for this one. Then delete the app. On a Mac, also delete the PrivateJournal folder inside your user Library folder; if that Mac is your sync server, the folder also holds the server’s data.
- **Your server.** Delete the server’s data and its backups, and any archives you exported.
- **Agent access.** Revoke it in Settings > Agent Access. Ask the agent’s provider about data it already received.

The [Privacy Policy](../../PRIVACY.md) explains what is stored where.

# Troubleshooting

## I forgot my master password

Your master password can’t be recovered, and your server can’t reset it: it never receives the password.

- **You still have a device with your journals.** Keep using it; it opens without the password. If you sync, you can also add devices by [pairing](devices.md#add-a-device), which doesn’t need the password.
- **Your journals are only on this device.** Choose Settings > Privacy > **Change Password…**, then **Forgot Password?**. After you confirm it’s you with Face ID, Touch ID, or your passcode or Mac login password, you can set a new password. Archives you exported before still need the old one.
- **Otherwise,** you can’t open encrypted archives, recover your journals on a new device, or change the password without the current one.

Save your password in a password manager so this doesn’t happen again.

## I can’t unlock My Journal

App Lock uses your device’s Face ID, Touch ID or passcode, or your Mac login password; there’s no separate PIN. If your device can’t authenticate you, choose **Use Master Password** (or your recovery key) on the lock screen. If you removed your device’s passcode, My Journal turns App Lock off the next time it opens.

## My Journal can’t open your journals

When My Journal can’t open the journals on your device, it shows **Your Journals Can’t Be Opened** instead of your journals. It says “Nothing has been removed.” and means it: opening only reads, and a damaged library is left exactly as it is. Your journals may still be fine. A busy device, a restart that hasn’t finished, a Keychain that can’t be read and a locked iPhone cause the same screen as a damaged file.

1. **Try Again.** Choose **Try Again**, or quit and reopen My Journal. On an iPhone or iPad that has just restarted, the screen goes away by itself once the device is unlocked and My Journal can reach its files. If you use App Lock, you unlock as usual afterwards.
2. **Restart your iPhone, iPad or Mac.** If it keeps happening, restart the device and open My Journal again.
3. **Keep a copy first.** Before you try anything that removes something, keep a copy. On a Mac, quit My Journal and copy the app’s folder (`~/Library/Containers/io.github.ralphkrauss.myjournal`, in Finder choose Go > Go to Folder…). On an iPhone or iPad you can’t reach the app’s files, so make a device backup.
4. **Restore from an archive.** If you have an archive you exported earlier, choose **Import Archive…**. My Journal checks the archive first, and only then replaces the journals it can’t open: they are removed from this device, and syncing with a server ends. App Lock stays on. The device stays in your server’s list of devices until you remove it in Settings > Devices on another device.
5. **Restore from your server.** If your journals are on a server, choose **Erase Journals and Settings…**, which appears after Try Again has failed once, then **Connect to a Server…** on the first screen. Your journals come back from the server. Changes that hadn’t synced are lost. If this device couldn’t be signed out of the server, remove it in Settings > Devices on another device.

### If your journals aren’t encrypted

If **Your Journals Can’t Be Opened** says “These journals aren’t encrypted, and this version of My Journal opens only encrypted journals.”, the journals on this device were made with version 1.0 and **Continue Without Encryption**. This version opens only encrypted journals, so it can’t open them. Nothing has been changed or removed, and there is no **Try Again** because trying again changes nothing.

- **To read them,** keep using version 1.0 (if you haven’t already updated this device), or export them from version 1.0 before you update: **Export as Markdown…** saves readable files, and a 1.0 archive of journals without encryption can’t be restored in this version.
- **To start over,** choose **Erase Journals and Settings…**. It removes the journals and settings from this device, then you can start a new encrypted journal or connect to a server. Only do this once you have a copy you want to keep.

### Update My Journal

**Update My Journal** means these journals were saved by a newer version. Update My Journal in the App Store or TestFlight to open them. The same screen appears when the settings saved on the device were written by a newer version: **Your Journals Can’t Be Opened** with “My Journal can’t read the settings saved on this device.” Update, then choose Try Again. There is no button for an update yet, so open the App Store or TestFlight yourself. If no newer build is available to you, there is no button on the screen that keeps the journals: deleting the app removes its files, and the device key stays in the Keychain until the next install and Erase.

### Settings that can’t be read

With unreadable settings, **Import Archive…** isn’t offered, because it would replace a file My Journal couldn’t read. If you have an archive, choose **Erase Journals and Settings…** first, then **Import Archive…** on the first screen.

### What Erase removes

**Erase Journals and Settings…** removes everything My Journal stores on the device, whether or not it can read it: the journals, the settings, copies left by earlier imports and exports, and the device’s keys. It keeps the files of the server earlier Mac builds ran, which may hold the only copy of other devices’ changes (see [If you used Use This Mac](#if-you-used-use-this-mac)). If the Keychain can’t be listed, Erase still removes the files and says nothing about it; a connection token may then remain, and you remove it by revoking this device in Settings > Devices on another device. If Erase can’t move the settings file (for example because of permissions), it says “Couldn’t Erase.” and removes nothing; deleting the app removes the files on iPhone and iPad.

With App Lock on, or when the settings can’t be read, Import and Erase ask you to confirm with Face ID, Touch ID or your passcode or Mac login password first.

### The lock screen asks for your password and you don’t have it

If your library needs a password and its device key is gone (it isn’t kept in a device backup), the lock screen asks for the master password or recovery key. Below it, **Don’t have your Master Password?** offers **Import Archive…** and **Erase Journals and Settings…**, which work as described above.

## Something changed on two devices

When the same entry or template changes on two devices before they sync, My Journal keeps both versions instead of choosing one, and doesn’t ask or alert you. The version from the device that synced last stays where it is. The other version is saved as a separate entry or template next to it, with “(other version)” added to its title. Nothing is lost, and nothing is overwritten.

On the device that kept both, the open entry shows a notice: “This entry was also changed on another device. The other version is saved as a separate entry.” If the other version was last changed later than this one, the notice says that version is newer. The clocks of the two devices decide that wording only.

1. Choose **Show Other Version** in the notice to open the other version, or **Dismiss** to close the notice.
2. To find it later, open Settings > Sync > **Changed on Two Devices** and choose its row.
3. Keep whichever you want. Delete the other version like any entry, or copy what you need from it into the first.

Other changes settle the same way, and Settings > Sync lists everything under **Changed on Two Devices**. Choosing a row opens the item it saved.

- **An entry or template changed on two devices.** Both versions are kept, as above. If the other device keeps typing, its later text replaces the saved copy as long as you haven’t changed that copy. If you moved an entry on one device and edited it on another, you get two entries, because My Journal doesn’t keep the original to compare with. If you deleted an entry on one device and edited it on another, the edited text stays in its journal and the other version is in **Recently Deleted**.
- **A journal renamed on two devices.** The journal keeps the name that reached the server last, which isn’t always the one you typed last. The row shows the name it has now and the other one. Choose **Rename…** if you prefer the other name.
- **Deleted permanently on one device and changed on another.** The item stays deleted, and the changed version is saved as a separate entry or template in **Recently Deleted**. Choose **Restore** to bring it back. If its journal is gone too, it is in **Unavailable Journals**, and **Restore** puts it in your Default Journal. A journal deleted permanently on one device and changed on another stays deleted.

Until the next sync finishes combining such a change, moving that entry, restoring an earlier version of it, or deleting it permanently says “Some changes from another device will finish combining when My Journal next syncs.”

If version 1.0 left changes for you to review, version 1.1 settles them the first time it opens your journals, keeping both versions. A deletion you had not yet confirmed stays deleted and the edit is saved separately.

The list shows the 20 most recent notes. A note disappears after 30 days, except a journal’s rename note, which stays until you choose **Clear List**. Clearing the list only forgets the notes; the entries and journals stay as they are.

If the section **Changed on Two Devices** isn’t there, nothing has been settled.

### “Update My Journal to combine them”

This line appears at the bottom of Settings > Sync when a change from another device was saved by a newer version of My Journal that this version can’t read. The change is held as it is, and nothing is lost or sent. Update My Journal on this device. It then settles the change by itself, and the line goes away.

## Sync isn’t working

Your changes are always saved on the device first; sync never deletes them. **Sync Status** shows what’s wrong: the cloud button in the toolbar on the Mac, or the entry’s … menu on iPhone and iPad. Choose **Sync Settings…** there, or open Settings > Sync, to see the message, **Last Synced**, how many items are **Not on Server Yet**, and the one action that fixes it. The cloud shows an exclamation mark when you need to act, or when changes have waited more than a day.

- **“You’re offline.”**, **“Can’t reach the server right now.”** or **“The server isn’t available right now.”** My Journal tries again by itself, and as soon as the network returns. Check your connection and, if you use Tailscale, that it’s connected. If your Mac is the server, check that it’s awake and that Settings > Sync on the Mac says Running. **Try Again** syncs at once.
- **“The server isn’t set up.”** The server was reset and waits for a setup code. Choose **Reconnect…** and enter the code your server shows (run `setup-code` on the server to see it again). This device’s journals become the server’s journals; your other devices then show “The server was restored or replaced…” and reconnect without copying anything twice.
- **“The server was restored or replaced and doesn’t recognize this device.”** Choose **Reconnect…** and enter your master password, or use a connected device. If the server holds your journals, they continue where they left off. If it holds someone else’s library, **Merge Journals** asks before anything is sent.
- **“This device no longer has access to the server.”** The device was removed in Settings > Sync > Devices on another device. To reconnect, you need your password or a connected device. Choose **Reconnect…**.
- **“Update My Journal to sync with this server.”**, **“The server needs an update…”** or **“This server needs an update before this device can connect.”** (the server software is older than My Journal expects; nothing on your devices is lost or changed), a certificate that isn’t valid, or an address that doesn’t lead to a My Journal server: fix the app or the server, then choose **Check Again**. My Journal also checks every few minutes.
- **“My Journal no longer runs a server on this Mac, so this Mac stopped syncing.”** See [If you used Use This Mac](#if-you-used-use-this-mac).
- **“My Journal can’t read your journals on this device.”** Nothing has been removed. Choose Export Archive in Settings ▸ Backup to keep a copy, then quit and reopen My Journal. If it keeps happening, see [My Journal can’t open your journals](#my-journal-cant-open-your-journals).
- **“Couldn’t sync right now. My Journal will try again.”** The journals on the device were busy or briefly unavailable. Nothing needs doing.

**Your server moved to a new address.** Choose Settings > Sync > **Stop Syncing…**, then **Connect to a Server…** with the new address. Your journals stay on the device, and nothing is copied twice.

After a server is reset or restored, agents need access again in Settings > Agent Access.

## If you used Use This Mac

Earlier test versions of My Journal for Mac could run a sync server inside the app. The app no longer includes one, so a Mac that used it stopped syncing, and devices that synced through it can’t reach their server. To sync again, follow [If you used Use This Mac](sync.md#if-you-used-use-this-mac) in the sync guide:

1. Set up a server elsewhere.
2. On the Mac, connect to it. The Mac’s journals are uploaded.
3. On each other device, choose **Stop Syncing…**, then connect to the new server and join it with the device’s journals. Changes that weren’t sent are kept.
4. On the Mac, turn off the old Tailscale Serve rule: `tailscale serve --https=443 off`, or `tailscale serve reset` if it was the only rule.
5. Connect your agents again. Their access belonged to the old server.

### The old server’s files

My Journal keeps the old server’s files on the Mac, in the app’s container: `~/Library/Containers/io.github.ralphkrauss.myjournal/Data/Library/Application Support/PrivateJournal` (in Finder, choose Go > Go to Folder…). They are `local-server.json`, `local-server-process.json`, `local-server.log`, the `local-server-data` folder, and `local-server-retired`, which records that the Mac already stopped syncing with that server. `local-server-data` may hold the only copy of changes another device sent that the Mac never received.

Erase Journals and Settings keeps these files, and on such a Mac its footer says so.

### Keep using the old server’s data

Instead of moving to a new server, you can run the old server’s data on the same Mac at the same address. Your other devices and agents then keep working, and only the Mac signs in again.

1. Quit My Journal and copy the `local-server-data` folder to a folder of your own, such as one in your Documents folder.
2. Start the [standalone server](../distribution.md#building-packages-locally) (`scripts/package-server.sh` builds it for macOS) with that copy as its data directory, on the old port: `Journal__DataDirectory=<copy> ASPNETCORE_URLS=http://127.0.0.1:46371 ./journal-server`. Your Tailscale Serve rule still forwards to that port; if you use another port, point the rule at it instead. Keep the server running and the Mac awake while your devices sync.
3. Open My Journal and choose Settings > Sync > **Connect to a Server…**. Enter `http://127.0.0.1:46371`, and sign in with your master password. For a library without a password, run the server once with `--recovery-code` (with the same `Journal__DataDirectory`) and use that code. Changes from your other devices download to the Mac.

The Mac stopped syncing by itself only once, so it stays connected this time.

### Remove the old server’s files

If the library on the Mac matters to you, [export an archive](backups.md#export-an-archive) first. Then quit My Journal and, in the folder above, delete `local-server.json`, `local-server-process.json`, `local-server.log`, the `local-server-data` folder and `local-server-retired`. Don’t delete the whole `io.github.ralphkrauss.myjournal` folder: it also holds your journals.

## An entry or image is too large to sync

If an entry is too large for the server, My Journal says “… is too large to sync. It’s saved on this device.” Shorten it or split it into separate entries; it syncs once it’s small enough. The limit is about 4 MB of text, much longer than a typical entry.

If an image is too large (over about 25 MB), entries that include it stay on this device. Use a smaller copy of the image instead.

## What is Unavailable Journals?

Unavailable Journals appears in the sidebar when some entries can’t be shown in their journal: the journal hasn’t arrived on this device yet, or it, or a change to it from another device, was saved by a newer version of My Journal. Your entries are still saved. Select an entry there to see why, and choose **Try Syncing Again** when offered, or update My Journal. If the entry is deleted, **Restore to “Name”** puts it in your Default Journal, which the button names.

## Move to a new device

- **If you sync:** [add the new device](devices.md#add-a-device). Your journals download to it.
- **If you don’t sync:** [export an archive](backups.md#export-an-archive) on the old device, copy the file to the new one, and choose **Import Archive…** on its first screen.

Then turn on App Lock and set up agent access again; they aren’t copied. Check that your journals arrived before you [erase the old device](#delete-your-data), and [revoke its access](devices.md#remove-a-device) if you don’t erase it.

## An archive won’t open

- **“Update My Journal to open this archive.”** The archive was made by a newer version. Update My Journal on this device.
- **“Couldn’t open this archive…”** from a device that still runs 1.0: 1.0 can’t open the single-file archives that 1.1 saves. Update My Journal on this device first. The folder archives that 1.0 saved still open in 1.1.
- **“This archive is incomplete or damaged.”** The file was cut short or changed, for example by a download that stopped. Copy or download it again. A file that was unpacked with an archive tool is no longer an archive; use the original file.
- **“Couldn’t open this archive. Check that the file is available and your device has enough space.”** The file may still be downloading from iCloud Drive or another service, or the device is too full. Opening an archive needs about twice its size free, plus 256 MB.
- **“There isn’t enough space to export the archive.”** Exporting needs room for the archive on the device (the database, the images and 256 MB), and on the place you save it to. Free up space, or save to another place. Nothing is saved when this appears.

## Delete your data

Nothing is deleted automatically.

- **Entries, journals and templates.** Deleting one moves it to Recently Deleted. There, choose **Delete Permanently…** to remove it and its earlier versions from this device, and from your other devices when they sync. Copies may remain in archives, backups and your server’s history, and images stay in the app’s storage.
- **Everything on a device.** Choose **Erase Journals and Settings…** at the end of Settings (on the Mac, at the end of Settings > General). It removes your journals, settings and server connection from this device, as if My Journal had just been installed, and signs the device out of your server. Journals already on your server stay there, and your other devices aren’t changed. If something isn’t on your server yet, or you don’t sync, My Journal says so first and offers **Export Archive…**; you can’t undo erasing. With App Lock on, you confirm with Face ID, Touch ID or your passcode. On a Mac that used Use This Mac, it keeps [the old server’s files](#the-old-servers-files).
- **Deleting the app** removes its data on iPhone and iPad. If you sync, first choose Settings > Sync > Devices on another device and **Revoke Access…** for this one. On the Mac, deleting the app leaves its data behind: to remove it too, quit My Journal, delete the app, and delete the `io.github.ralphkrauss.myjournal` folder in the Containers folder inside your user Library folder.
- **Your server.** Delete the server’s data and its backups, and any archives you exported.
- **Agent access.** Revoke it in Settings > Agent Access. Ask the agent’s provider about data it already received.

The [Privacy Policy](../../PRIVACY.md) explains what is stored where.

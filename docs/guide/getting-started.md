# Getting started

## Install My Journal

Get My Journal from the App Store, where one purchase covers iPhone, iPad and Mac, with no subscription or in-app purchases. You can also build it from source for free on a Mac with Xcode; see [development](../development.md).

It runs on iOS 16, iPadOS 16 and macOS 14 or later, on Mac computers with Apple silicon or an Intel processor.

## Create your journal

1. Open My Journal and choose **Start a Journal**.
2. Choose **Use Encryption**.
3. Enter a master password twice, save it in your password manager, and choose **Create**.

My Journal creates your first journal, named Default. You can start writing right away; nothing leaves the device unless you set up [sync](sync.md).

To rename a journal, Control-click it in the sidebar on the Mac, or touch and hold it on iPhone and iPad, and choose **Rename…**. To add another journal, for example to keep work notes apart, choose **New Journal**: in the File menu on the Mac (⌥⌘N), or the folder button in Journals on iPhone and iPad.

Already use My Journal on another device? Choose **Connect to a Server…** on the first screen instead: scan the code your other device shows, or sign in with your master password (see [Add a device](devices.md#add-a-device)). To start from a backup, choose **Import Archive…** (see [Backups](backups.md)).

## Your master password

Your master password protects the key that encrypts your journals. You need it to set up sync, to open your archives, and to recover your journals on a new device.

- A longer password is harder to guess. A password manager can generate and remember one for you.
- Save it in your password manager, apart from your backups.
- Nobody can reset it for you. Your server stores only a copy of your journals’ key that is locked with the password, never the password itself. If you lose both your password and access to your devices, your journals can’t be recovered.
- To change it, choose Settings > Privacy > **Change Password…**. You need the current password. Archives you exported earlier still open only with the password you had then.

If you’ve forgotten it, see [Troubleshooting](troubleshooting.md#i-forgot-my-master-password).

## Encryption

Encryption is on by default. Your entries, journal names, templates, image descriptions and images are encrypted on your device before they’re stored or synced, so a server you sync with can’t read them. The [security model](../../SECURITY.md) explains what is protected and what a server can still see.

When you start, you can choose **Continue Without Encryption** instead. Then there is no master password, and anyone with access to your files, server or backups can read your journals.

To turn encryption on later, open Settings > Privacy and choose **Turn On Encryption…**. Choose a master password and enter it again to verify it, then choose **Turn On**. You can’t write while your journals are being encrypted. Encryption can’t be turned off again.

If your journals sync, update My Journal on your other devices and let them sync first. Afterwards, sign in on each of them with the new master password (**Reconnect…** appears where the sync problem shows), or add them from this device. Agents with access through your server must be given access again. Archives and backups made earlier stay unencrypted, so make a new archive and delete the old ones.

## Write

- **New entry.** Choose **New Entry** in the toolbar (⌘N). It always starts an empty entry in the journal you are looking at, or in your Default Journal when you are not looking at one (Settings > General).
- **Formatting.** Use the **Formatting** button in the toolbar, or the Format menu on the Mac, for headings, bold, italic, lists, checklists, quotes and code. Tables, links, horizontal rules and code blocks are under Insert. To change a link, put the insertion point in it and choose Insert > **Edit Link…** (⌘K on a Mac or with a keyboard); to take a link off its text, choose **Remove Link**. A selection that covers only part of a link removes the whole link. Changing a link’s text gives all of it the formatting of its first character. With the insertion point at the end of a link, ⌘K edits that link; type a character first to add a new link after it. Typing “- ”, “1. ”, “[ ] ”, “# ” or “> ” at the start of a line formats it; press Delete right after to keep what you typed. You can turn this off in Settings > General on the Mac (Writing on iPhone and iPad).
- **Lists and checklists.** Press Return for the next item and Return on an empty item to end the list. **Increase Indent** and **Decrease Indent** (⌘] and ⌘[ with a keyboard) nest an item under the one above. To check off an item, tap or click its checkbox.
- **Photos and images.** Choose **Insert Image** to add several at once: on iPhone and iPad from **Photo Library**, **Take Photo** or **Choose File…**; on the Mac, choose Format > Insert > **Image…** or drag images in. Touch and hold an image (Control-click on the Mac) to copy, share, save or delete it, or to add **Image Descriptions…** for VoiceOver. Where a photo was taken is removed when you add it.
- **Templates.** A new library has none. To make one, choose **Save as Template…** in an entry’s actions (the … button, or Control-click or touch and hold the entry in the list). To start an entry from a template, open an empty entry and choose **use a template**, or choose **Use a Template…** in the File menu (Mac, and iPad with a keyboard). The template fills that entry and keeps its title.
- **Dates.** Every entry has a date, shown in the list. To change it, choose **Change Date…** in the entry’s actions.
- **Search.** Use the search field, or Edit > **Search Entries** (⌥⌘F) on the Mac.
- **Focus on writing.** On the Mac, choose View > **Show Editor Only** (⇧⌘D) to hide the sidebar and entry list. Choose View > **Show Sidebar and List** to bring them back.
- **Earlier versions.** Choose **Version History…** in the entry’s actions to see earlier versions and restore one as a new entry. When you start changing an entry or template, My Journal keeps the version from before, then one every 10 minutes while you keep writing. It keeps the 50 most recent of these for each entry or template, and every version kept when you review changes. Earlier versions stay on this device; they aren’t synced.
- **Deleted items.** Deleted entries, journals and templates go to **Recently Deleted**, where you can restore them. They stay there until you delete them permanently; **Delete All** empties Recently Deleted. **Restore** brings an item back at once. If an entry’s journal has been deleted, the button names the journal it goes to, your Default Journal, for example **Restore to “Personal”**. To bring back a deleted journal with its entries, open it in Recently Deleted and choose **Restore Journal**. With a keyboard, ⌘Z right after deleting an entry or template brings it back.

## Organize

- **Journals.** Keep separate journals, for example for personal and work notes. To change their order, drag them in the sidebar on the Mac; on iPhone and iPad, choose **Edit** in Journals and drag the handles. The order is the same on all your devices when they sync.
- **Pinned entries.** Choose **Pin Entry** in an entry’s actions to keep it at the top of its journal and of All Entries, under **Pinned**. **Unpin Entry** puts it back in date order.
- **Move an entry.** Choose **Move Entry…** in the entry’s actions to file it in another journal. Journal names are unique, so when sync, an import or **Merge Journals** meets a name that is taken, it adds a number to the newer journal, for example “Work 2”. To keep both, choose **Rename…** and give the numbered journal a name of its own. To combine two journals into one, move the entries one at a time with **Move Entry…**, then delete the empty journal. A journal’s name that was changed by mistake is changed back with **Rename…**.
- **All Entries** shows the entries of every journal together.

## Update My Journal

- **App Store:** updates arrive like those of other apps.
- **Built from source:** get the latest source and build again. Your journals are kept.

Keep all your devices on the same version. A version can’t open journals saved by a newer one; it says “Update My Journal” and leaves them unchanged. Don’t go back to an older version. Export an [archive](backups.md) before you update. If you run your own server, update it as described in [self-hosting](../self-hosting/README.md#updates).

# Backups

An archive is a copy of all your journals in one file: entries, templates, images, earlier versions and Recently Deleted. It’s encrypted and opens only with your master password, so you can attach it to a message, send it by AirDrop or copy it to an external drive as it is.

An archive doesn’t include your server connection, your devices, App Lock or agent access. Set those up again after a restore.

Your server is not a backup: it can fail or lose data too. Export an archive regularly and before you update, and keep it somewhere other than the device, such as an external drive.

## Export an archive

1. Choose Settings > Backup > **Export Archive…**. On the Mac, you can also choose File > **Export Archive…**.
2. Choose where to save the archive. It’s saved as a file such as `Journal Archive 2026-10-10.journalbackup`; leave the ending as it is, because it’s how My Journal recognizes the file.

If you’re not sure of your master password, choose **Change Password…** under “Not sure of your password?” below the button first: typing the current password there checks it.

Keep your master password separate from your archives. An archive opens only with the password you had when you exported it, even if you change your password later.

Exporting needs room for the archive on the device first, and on the place you save it to. If either is too full, My Journal says so and saves nothing.

Archives made by My Journal 1.0 were folders ending in `.journalarchive`. 1.1 still opens them when they are encrypted; a folder archive made by 1.0 for journals without encryption doesn’t open (My Journal says it couldn’t open the archive). But 1.0 can’t open the single file that 1.1 saves, so update My Journal on every device before you move an archive between them.

## Restore journals on a new device

1. Open My Journal and choose **Import Archive…** on the first screen. You can also open the archive file itself with My Journal.
2. Enter the archive’s password and choose **Continue**. My Journal shows what the archive contains.
3. Choose **Restore Journals**.

To sync the restored journals, [set up sync](sync.md) in Settings.

## Import into your current journals

1. Choose Settings > Backup > **Import Archive…** (on the Mac, also File > **Import Archive…**).
2. Enter the archive’s password and choose **Continue**.
3. Choose **Import as New Journals**.

Your current journals are kept, and the ones from the archive are added as separate journals. If you sync, they’re uploaded to your server too.

## Export as Markdown

Export as Markdown saves your journals as plain Markdown files that any Markdown app can open, such as Obsidian or iA Writer. It isn’t a backup: My Journal can’t import it. To keep a copy you can restore, [export an archive](#export-an-archive).

1. Choose Settings > Backup > **Export as Markdown…**. On the Mac, and on iPad with a keyboard, you can also choose File > **Export Journals as Markdown…**.
2. If App Lock is on, confirm with Face ID, Touch ID or your passcode or Mac password.
3. Choose where to save the folder, named `Journal Markdown` with the date.

The folder holds:

- a folder for each journal, with one file for each entry, named with its date and title, such as `2026-10-05 Morning pages.md`. Each file starts with front matter: the title, dates, journal and whether the entry is pinned or archived;
- the images, in an `attachments` folder beside the entries. HEIC photos are converted to JPEG, so other apps can show them;
- your templates, in a `Templates` folder.

Recently Deleted, earlier versions, and the other version of an entry whose [change from another device](troubleshooting.md#something-changed-on-two-devices) is held until you update My Journal aren’t included. When both versions were kept, the other one is a separate entry and is included. If something was left out, such as images that haven’t downloaded yet, a note under the button says what and what to do, for example to export again after syncing.

The files aren’t encrypted, even when your journals are, so anyone with the folder can read them. Photos keep their original metadata, which can include where they were taken; check before you share the files. The exact format is in [Markdown export](../../protocol/markdown-export.md).

## Back up your server

If you run your own server, back it up as well; see [self-hosting](../self-hosting/README.md#backups). A server backup lets you restore the server; an archive lets you restore your journals in the app.

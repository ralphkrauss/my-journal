---
id: create-library
title: Create a library (Start a Journal)
features: [create-library, encrypt-library, continue-without-encryption]
sources:
  - apps/apple/JournalApp/Views/CreateJournalView.swift
  - apps/apple/JournalApp/Model/NewVault.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - docs/design/markdown-writing-revision.md
  - docs/design/no-built-in-templates-2026-10-04.md
  - docs/guide/getting-started.md
---

# Create a library

## Purpose

Creates this device's library from **Start a Journal** on the welcome screen, with a master password (encrypted, the default path) or without encryption.

## Entry points

- `library.welcome.start` on screens/welcome.

## Content

A sheet with two steps. Both steps show, in a left-aligned column (at most 480 points wide):

1. Decorative symbol (a shield on step 1, a key on step 2).
2. Heading: `common.protectYourJournals` (step 1) or `common.chooseMasterPassword` (step 2).
3. Secondary text: `library.createLibrary.explanation`.

**Step 1, Protect Your Journals**

4. Primary action, large and prominent: `library.createLibrary.useEncryption`.
5. Secondary action styled as a link: `library.createLibrary.continueWithout`, with `common.unencryptedWarning` under it in smaller secondary text.

**Step 2, Choose a Master Password**

4. Secure field, placeholder `common.masterPassword`. Return moves to the next field.
5. Secure field, placeholder `common.verify`. Return submits (as Create).
6. Inline problem text in red, when there is one (`messages.connection.passwordsDontMatch`).
7. Toggle `common.showPassword`: shows both fields as plain text.
8. Smaller secondary text: `library.createLibrary.advice`.

Both steps, when present:

- Error text in red: the error that stopped creation (for example `messages.password.enterMaster`).
- Progress indicator with `library.createLibrary.creating` while the library is created.

**Bar buttons**

- Cancel (`common.cancel`), cancellation placement. On iPhone and iPad step 2 shows the system back button instead.
- Step 2 only: Create (`common.create`), confirmation placement. On the Mac also Back (`common.back`), which returns to step 1.

## Steps

1. The person chooses **Use Encryption**. Step 2 appears (pushed on iPhone and iPad, replacing step 1 in the same sheet on the Mac) and the first password field takes focus once it is on screen.
2. They type the password twice and choose **Create** (or Return in Verify).
   - **Create** is enabled only when both fields are non-empty and nothing is being created.
   - If the two fields differ, nothing is created: `messages.connection.passwordsDontMatch` appears under the fields, is announced, and focus moves to Verify. Editing either field clears the message.
3. The library is created: a new library with one journal named `library.createLibrary.defaultJournalName` and no templates. The sheet closes and both fields are cleared. The library window opens on that journal (empty, offering New Entry).

**Without encryption:** on step 1, **Continue Without Encryption** creates the library at once, without a confirmation. The result is the same, unencrypted, with no master password.

**Cancel:** closes the sheet, clears the fields and creates nothing. The welcome screen stays.

## States

- **Busy:** while creating, every control is disabled, the sheet can't be dismissed by swiping, the back button is hidden, and `library.createLibrary.creating` shows.
- **Error:** creation failed (for example the device's keychain refused the key). The error text shows in red in the sheet; nothing is left behind (a partly created library is removed). The person can try again or cancel.

## Rules

- The password is checked only for being non-empty (the minimum length is one character). There is no strength meter.
- The two fields are compared only on Create, not while typing.
- The password fields offer the system's password manager suggestions for a new password, and turn off autocorrection and autocapitalization.
- A library created here is confirmed at once (no recovery-key step). The library's key is stored in the device's secure storage; the password protects the copy used for recovery, backups and sync.
- New libraries start without templates (no-built-in-templates-2026-10-04.md).
- Encryption can be turned on later (Settings ▸ Privacy ▸ Turn On Encryption…, screens/settings-privacy) but never off.

## Accessibility

- The symbols are decorative.
- The mismatch is announced when it appears.
- Focus moves to Master Password when step 2 appears, and to Verify after a mismatch.
- The sheet scrolls at large text sizes.

## Platform notes (Apple)

- **iPhone and iPad:** step 2 is pushed inside the sheet, with the system back button (and swipe back) in Cancel's place, as in the connection flow.
- **Mac:** one sheet (520 points wide; 420 points tall on step 1, 580 on step 2) with Cancel, Back and Create in its toolbar.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).

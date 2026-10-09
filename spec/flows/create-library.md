---
id: create-library
title: Create a library (Start a Journal)
features: [create-library, encrypt-library]
sources:
  - apps/apple/JournalApp/Views/CreateJournalView.swift
  - apps/apple/JournalApp/Model/NewVault.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - docs/design/markdown-writing-revision.md
  - docs/design/no-built-in-templates-2026-10-04.md
  - docs/design/1-1-encryption-and-passwords.md
  - docs/guide/getting-started.md
---

# Create a library

## Purpose

Creates this device's library from **Start a Journal** on the welcome screen, with a master password. Every new library is encrypted; there is no way to create one without encryption.

## Entry points

- `library.welcome.start` on screens/welcome.

## Content

One sheet, one step: **Choose a Master Password**. In a left-aligned column (at most 480 points wide):

1. A key symbol (decorative).
2. Heading: `common.chooseMasterPassword`.
3. Secondary text: `library.createLibrary.explanation`.
4. Secure field, placeholder `common.masterPassword`. Return moves to the next field.
5. Secure field, placeholder `common.verify`. Return submits (as Create).
6. Inline problem text in red, when there is one (`messages.connection.passwordsDontMatch`).
7. Toggle `common.showPassword`: shows both fields as plain text.
8. Smaller secondary text: `library.createLibrary.advice`.
9. Error text in red: the error that stopped creation (for example `messages.password.enterMaster`).
10. Progress indicator with `library.createLibrary.creating` while the library is created.

**Bar buttons:** Cancel (`common.cancel`), cancellation placement; Create (`common.create`), confirmation placement, Return. The first field takes focus when the sheet appears.

## Steps

1. The person types the password twice and chooses **Create** (or Return in Verify).
   - **Create** is enabled only when both fields are non-empty and nothing is being created.
   - If the two fields differ, nothing is created: `messages.connection.passwordsDontMatch` appears under the fields, is announced, and focus moves to Verify. Editing either field clears the message.
2. The library is created: a new library with one journal named `library.createLibrary.defaultJournalName` and no templates. The sheet closes and both fields are cleared. The library window opens on that journal (empty, offering New Entry).

**Cancel:** closes the sheet, clears the fields and creates nothing. The welcome screen stays.

## States

- **Busy:** while creating, every control is disabled, the sheet can't be dismissed by swiping, and `library.createLibrary.creating` shows.
- **Error:** creation failed (for example the device's keychain refused the key). The error text shows in red in the sheet; nothing is left behind (a partly created library is removed). The person can try again or cancel.

## Rules

- **Choosing a master password** follows the shared rule in `spec/README.md` (Master passwords): two fields, both new-password fields, the two must match, no minimum length and no strength meter. The note under the fields (`library.createLibrary.advice`) and, later, the line on the Encrypt Your Journals Done sheet carry the safety weight.
- The two fields are compared only on Create, not while typing.
- The password fields offer the system's password manager suggestions for a new password where the system does so, and turn off autocorrection and autocapitalization. Whether the system offers a strong password for an app with no associated web domain is unverified ([open-questions.md](../open-questions.md), D61), so the spec promises nothing.
- A library created here is confirmed at once (no recovery-key step). The library's key is stored in the device's secure storage; the password protects the copy used for recovery, backups and sync.
- New libraries start without templates (no-built-in-templates-2026-10-04.md).
- Nothing creates an unencrypted library: Start a Journal, Connect to a Server and restoring an archive all end encrypted. A library made by an earlier version without encryption is encrypted by `screens/encrypt-journals`. Encryption can't be turned off.

## Accessibility

- The symbol is decorative.
- The mismatch is announced when it appears.
- Focus moves to Master Password when the sheet appears, and to Verify after a mismatch.
- The sheet scrolls at large text sizes.

## Platform notes (Apple)

- **iPhone and iPad:** the sheet no longer pushes a page; Cancel and Create are in its bar.
- **Mac:** one sheet 520 × 580 points with Cancel and Create in its toolbar; the sheet has no Back button.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).

# Export compliance (encryption)

Analysis and recommendation for the owner, written on 2026-10-05 for build 16. This isn't legal advice: the developer is responsible for the answer given to Apple, and Apple says so on its [overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance).

## Recommendation

**Keep `ITSAppUsesNonExemptEncryption = false` in both apps (`apps/apple/project.yml`).** If App Store Connect asks the encryption questions anyway, answer that the app uses encryption, and for the algorithm type choose **None of the algorithms mentioned above**. No documents need to be uploaded, and France can stay in the availability list.

This holds as long as every cryptographic algorithm in the apps is the one provided by Apple's operating system. Revisit it before adding any cryptographic library, such as SQLCipher, libsodium, a managed Argon2 implementation, OpenSSL or BouncyCastle.

## What the app uses

From a search of the code on 2026-10-05:

| Where | Algorithms | Provided by |
| --- | --- | --- |
| Journal content, images and archives (`JournalCore/Crypto.swift`, `Archive.swift`, `StoreReencryption.swift`) | AES-256-GCM | CryptoKit |
| Master password (`CJournalCrypto/JournalCrypto.c`) | PBKDF2-HMAC-SHA256, 600,000 iterations | CommonCrypto (`CCKeyDerivationPBKDF`) |
| Key wrapping, server authentication secret | AES-GCM, HKDF-SHA256 | CryptoKit |
| Adding a device (`Pairing.swift`, `PairingInvite.swift`) | Curve25519 key agreement, HKDF-SHA256, AES-GCM, SHA-256, HMAC-SHA256 | CryptoKit |
| Agent copy (`AgentCopy.swift`) | HKDF-SHA256, HMAC-SHA256, AES-GCM | CryptoKit |
| Random numbers | `SecRandomCopyBytes` | Security framework |
| Keys at rest | Keychain | Security framework |
| Network | TLS through URLSession | The operating system |

Until 2026-10-05 the Mac app also bundled the sync server, whose .NET cryptography goes through the same system frameworks on macOS. The server was then removed from the app, so the Mac build contains no .NET code. The server is distributed separately, outside the App Store.

Third-party code contains no cryptography: the Swift dependencies are GRDB (with the system SQLite), swift-markdown and swift-cmark.

The app does use encryption for more than authentication or HTTPS: it encrypts the person's journals end to end. That doesn't make it "non-exempt" in Apple's terms. What matters for App Store Connect is who provides the algorithms, not what they protect.

## Apple's guidance

- Apple's [export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption) has three cases:
  - "Encryption limited to that within the Apple operating system": no documentation required in App Store Connect.
  - An industry-standard algorithm that is *not* provided within the Apple operating system: upload the French encryption declaration, only when distributing in France.
  - Proprietary or non-standard algorithms: upload a U.S. CCATS and the French declaration.
- [`ITSAppUsesNonExemptEncryption`](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption): set it to NO when the app uses only encryption that's exempt from export compliance documentation. YES is normally paired with `ITSEncryptionExportComplianceCode`, a code Apple issues after reviewing uploaded documents. Without the key, App Store Connect asks the questions for every build.
- [Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations): encryption provided by the operating system is typically exempt from the documentation upload.
- The [overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance) still asks developers to make a determination for cryptography in Apple's operating systems too, and France's controls are named there for secure storage and secure communication apps, which describes My Journal.

### The questions App Store Connect asks

If the key is missing or App Store Connect asks anyway (for example when you select a build), the questions are, as currently worded in App Store Connect (taken from Apple's developer forums, since Apple's help pages don't quote them; check the wording on screen):

1. Does your app use encryption? **Yes.**
2. What type of encryption algorithms does your app implement?
   - Encryption algorithms that are proprietary or not accepted as standard by international standard bodies (IEEE, IETF, ITU, etc.)
   - Standard encryption algorithms instead of, or in addition to, using or accessing the encryption within Apple's operating system
   - Both algorithms mentioned above
   - **None of the algorithms mentioned above** ← choose this

"None of the algorithms mentioned above" is the same answer as `ITSAppUsesNonExemptEncryption = false`, and leads to no documentation. If a further question about distribution in France appears, answer it consistently: the app uses only the operating system's encryption.

Don't choose "Standard encryption algorithms instead of, or in addition to…": that describes an app that ships its own implementation (for example libsodium). It would require the French declaration for distribution in France, and it doesn't match what the app does.

## U.S. export rules

- Standard cryptography in a mass-market consumer app is typically classified 5D992.c and exported under License Exception ENC § 740.17(b)(1). Since BIS's March 29, 2021 rule, items in this group need no self-classification report and no classification request ([BIS summary of the 2021 changes](https://www.bis.gov/media/documents/table-changes-enc-wa2019-rule-final-version.pdf); [15 CFR 740.17](https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-740/section-740.17)). The annual report in § 740.17(e)(3) applies to components and to executable software derived from hardware, which this app isn't.
- **Open source.** Publicly available encryption source code needed an email notification to BIS and the NSA before 2021. The same rule limited that notification to "non-standard cryptography" (now [15 CFR 742.15(b)](https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-742/section-742.15)). My Journal's public source uses only standard algorithms, so no notification is needed. If non-standard cryptography is ever added, email `crypt@bis.doc.gov` and `enc@nsa.gov` with the repository URL before publishing it.

## France

French law requires a declaration to ANSSI for supplying or importing cryptography that does more than authentication or integrity ([ANSSI: contrôle des moyens de cryptologie](https://cyber.gouv.fr/reglementation/reglementation-identite-confiance-numerique/controles-reglementaires-cryptographie/controle-moyen-de-cryptologie/); [décret 2007-663](https://www.legifrance.gouv.fr/loda/id/JORFTEXT000000646995)). Apple's process asks for the French declaration only when the app's encryption is *not* provided by Apple's operating system, or is proprietary. With the answer above, App Store Connect asks for nothing, and the app can be available in France.

## Documentation to keep

No documents go to Apple. Keep this record, and the commit it describes, as the basis for the answer:

- this file and the code search it summarizes;
- `apps/apple/project.yml` (`ITSAppUsesNonExemptEncryption: false` for both apps);
- the dependency lock file (`apps/apple/Packages/JournalCore/Package.resolved`), which shows no third-party cryptography.

## When to answer again

- Before adding any cryptographic library, or an algorithm the operating system doesn't provide (for example Argon2 or XChaCha20 from a package).
- Before either app includes code from another runtime, such as a server.
- If Apple changes the questions or the documentation table linked above.

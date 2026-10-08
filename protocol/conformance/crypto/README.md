# crypto

Key derivation, recovery envelopes, sealed records and images, password normalization, passwordless libraries, pairing grants and what must be refused. The contract is [Encrypted content, Recovery formats and Pairing](../../README.md) in the protocol README.

| File | Covers | Produced by |
| --- | --- | --- |
| `encryption-v1.json` | Record and attachment envelopes, format 1 recovery (generated recovery phrase) | .NET 10 |
| `encryption-v2.json` | Formats 2 and 3 (password), password normalization, format 4 (no password), check-code pairing and its sealed grant, a current Markdown record with its image | The Apple app's derivation, pairing and record code, sealed with CryptoKit using fixed nonces |
| `negative-v1.json` | Sealed values that must not open (a changed byte, another key, another kind or ID in the context, an upper-case ID, too few bytes), recovery parameters outside the accepted range, base64 that isn't canonical | Swift, from the record vector of `encryption-v1.json` |

Both languages check these files: the server's `ProtocolVectorTests` and `CryptoNegativeConformanceTests` recompute every value with .NET's independent cryptography and the server's own verifier, commitment and input-bound code; Swift `InteroperabilityTests`, `InteroperabilityV2Tests` and `ConformanceCryptoTests` check them through CryptoKit, CommonCrypto and the application's actual decryption, recovery, pairing and record-decoding APIs. Keeping the expected bytes in shared static files prevents either implementation silently changing the protocol and passing only its own round-trip test.

## Encoding contract

- Binary JSON values use standard padded base64, not URL-safe base64. `context`, passwords and recovery text are UTF-8. UUIDs in authenticated contexts are lowercase, hyphenated strings.
- Each envelope uses AES-256-GCM, a 32-byte key, 12-byte nonce and 16-byte authentication tag. `combined` (and `wrappedKey`) contain **nonce || ciphertext || tag**. The UTF-8 `context` is authenticated additional data and is not included in `combined`. The nonce is therefore the first 12 bytes of each encoded value.
- The record context binds both record kind and ID. The attachment context binds its ID. Opening ciphertext under another context must fail authentication.
- `plaintext` is the exact byte input. Record JSON contains non-ASCII title/body text; decode it as UTF-8, retaining its values. JSON whitespace/key ordering and escaping are not canonicalized before encryption (the Apple app writes sorted keys and escapes `/` as `\/`). A client may serialize its own supported record representation; it must authenticate the received bytes before parsing them.
- Recovery authentication uses HKDF-SHA256 over the derived key with empty salt, info `journal:v1:recovery-auth` (for every format), and 32-byte output, encoded as lowercase hexadecimal. The server stores only `SHA-256(UTF-8 of that hex text)`, also lowercase hexadecimal.

## Format 1 (`encryption-v1.json`)

- Recovery derivation trims surrounding whitespace/newlines, UTF-8 encodes the remaining phrase without case folding or Unicode normalization, and runs PBKDF2-HMAC-SHA256 with a 16-byte salt, 600,000 iterations and 32-byte output. The app generates ASCII hexadecimal recovery phrases; this fixture additionally exercises non-ASCII UTF-8 handling and ASCII surrounding whitespace. It does not establish equivalence between every platform's Unicode whitespace classifications.
- The recovery context is `journal:v1:recovery`; the recovery envelope encrypts the vault key with the derived key. Its formatVersion is 1.
- The record plaintext is a legacy `version: 1` block document.

## Formats 2–4, pairing and current records (`encryption-v2.json`)

`corpusVersion` identifies this file's layout. One vault key (`recovery.vaultKey`, 32 bytes) runs through the whole file: the password envelopes wrap it, the pairing grant delivers it as `masterKey`, and it encrypts the record and image.

`recovery` — master password (format 2) and legacy access password (format 3):
- `password` has surrounding spaces, a precomposed `é` (U+00E9) and a four-byte emoji. `passwordUTF8` is its byte sequence, which is already in Unicode NFC and is the PBKDF2 password: formats 2 and 3 never trim. A client that trims (as format 1 does) derives another key.
- `derivedKey` = PBKDF2-HMAC-SHA256(`passwordUTF8`, `salt` (16 bytes), 600,000 iterations, 32 bytes). `recoverySecret` and `recoveryHash` are derived as above.
- Each `envelopes` item is a whole envelope as POST /v1/recovery (in `envelope`) and GET /v1/recovery/envelope return it (`salt`, `wrappedKey`, `iterations`, `formatVersion`); GET /v1/recovery returns it without `wrappedKey` from servers with the `private-envelope` capability. `wrappedKey` is 60 bytes: nonce (12) || AES-256-GCM(`derivedKey`, vault key (32)) || tag (16), with context `journal:v{formatVersion}:recovery`. Both items share the password and salt, so the context alone distinguishes them: opening a format 2 envelope as format 3 fails. Format 2 content is encrypted; format 3 content is stored and synced as plaintext.

`normalization` — a password typed with decomposed characters (formats 2 and 3):
- `password` has surrounding spaces, letters followed by combining accents (such as `e` + U+0301) and U+212B ANGSTROM SIGN. `typedUTF8` is its exact byte sequence; `normalizedUTF8` is the UTF-8 of its Unicode NFC form, the PBKDF2 password of every envelope created now.
- `normalized` holds `derivedKey`, `recoverySecret`, `recoveryHash` and a format 2 `envelope` derived from `normalizedUTF8`, as current clients create it. `exact` holds the same values derived from `typedUTF8`, as clients created envelopes before normalization. Both use `salt` and wrap `recovery.vaultKey`. A client typing `password` must open both: it derives from the NFC form first and, because the typed bytes differ, from the exact bytes second (protocol/README.md, Recovery formats).

`passwordless` — format 4:
- `envelope` has empty `salt` and `wrappedKey`, `iterations` 0 and `formatVersion` 4. There is no key material.
- `recoveryCode` is a one-use administrator code as `Journal.Api --recovery-code` prints it: 32 random bytes as 64 lowercase hexadecimal characters. The client sends it as the `recoverySecret` of POST /v1/recovery (the Apple app trims and lowercases what the person types); `recoveryHash` is what the server stores and compares.

`pairing` — check-code pairing (protocol/README.md, Pairing):
- The key pairs are the X25519 test keys of RFC 7748 section 6.1 (approver: Alice; new device: Bob), so any X25519 implementation can be cross-checked against the RFC. Private and public keys are raw 32-byte values; `sharedSecret` is the raw 32-byte X25519 output. .NET has no portable X25519, so only Swift recomputes the key agreement; .NET checks everything that follows from `sharedSecret`.
- `keyCommitment` = base64(SHA-256(UTF-8 `journal:v2:pairing-commitment` || device public key)).
- `checkCode`: the first four bytes, big-endian unsigned, of SHA-256(UTF-8 `journal:v2:pairing-check:{id}:` || device public key || approver public key), modulo 1,000,000, as six digits with leading zeros.
- `grantKey` = HKDF-SHA256(`sharedSecret`, salt = UTF-8 of the lowercase pairing `id`, info `journal:v1:pairing`, 32 bytes).
- `grantPlaintext` is the UTF-8 JSON the approving device seals; `grant` lists its values (`masterKey` base64, `recoveryVersion`, and `token`, the new device's bearer credential of 64 hexadecimal characters). `deviceTokenHash` is what the server stores for that credential.
- `encryptedGrant` = approver public key (32) || nonce (12) || AES-256-GCM(`grantKey`, `grantPlaintext`) || tag (16), with context `journal:v1:pairing:{id}`. The server refuses a grant whose first 32 bytes are not the approver key it recorded; the new device refuses one whose first 32 bytes are not the approver key its check code was computed from.

`content` — a record and the image it shows, both encrypted with `key`:
- `record.plaintext` is a record as the Apple app writes it today: an `entry` with a `version: 2` Markdown document, `metadata` (`blockIDs`, `segmentLengths`, `imageTypes`) and an image reference `attachments/{attachment id}`. `expected` lists the values a reader must obtain. The Apple app writes UUIDs inside record JSON in upper case, while contexts and the wire use lower case; compare UUIDs case-insensitively.
- `record.combined` uses context `journal:v1:record:entry:{id}`; `attachment.combined` uses `journal:v1:attachment:{id}`. Encrypted records and images are at least 29 bytes (nonce, tag and one byte).
- In formats 3 and 4 the same record is synced as base64 of `record.plaintext` itself, and an image as its raw bytes; no context applies.

## Values that must be refused (`negative-v1.json`)

- `open`: each item has a `key`, `context`, `combined` and `result`. `opens` has the `plaintext` it gives; `authenticationFails` must not open, however a client reports it. The cases change the record vector of `encryption-v1.json`: one tag, ciphertext or nonce byte, another key, a context naming another kind or record, an upper-case UUID in the context (contexts are lower case), an attachment context, no context, and values with fewer bytes than a nonce and a tag.
- `recoveryParameters`: `clientAccepts` is whether a client derives with these parameters (100,000 to 2,000,000 iterations and a 16-byte salt); `serverAcceptsOnSetup` is whether POST /v1/setup accepts them (exactly 600,000 iterations and a 16-byte salt).
- `base64`: `canonical` pairs bytes (hex) with their text; `rejected` lists texts a reader must not accept: missing padding, non-zero padding bits, whitespace or line breaks, the URL-safe alphabet.

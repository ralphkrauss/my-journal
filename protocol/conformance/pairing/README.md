# pairing

Pairing a new device ([Pairing and Invite pairing](../../README.md#pairing) in the protocol README). The key agreement and the sealed grant are in [../crypto/encryption-v2.json](../crypto/README.md); this folder has the rest of the derivations.

| File | Covers | Produced by |
| --- | --- | --- |
| `pairing-v1.json` | The invite proof (message bytes and HMAC), the text of an invite code, how a server address becomes the origin the proof binds, what scanning other text concludes, and the six-digit check code with the key commitment | Swift; the protocol README's vectors are included and checked separately |

- `inviteProofs`: the inputs (`handle`, `approverKey`, `commitment`, `secret`, `server`, `deviceName`; binary values in base64), the normalized `origin`, the `message` that is authenticated (`journal:v2:pairing-invite`, a zero byte, the handle, the approver key, the commitment, then the origin and the device name each with a two-byte big-endian length), the `proof` (HMAC-SHA256 with the secret, base64) and the QR `text`: `MYJOURNAL1.` and base64url without padding of handle ‖ approver key ‖ secret ‖ UTF-8 server address.
- `origins`: `address` to `origin` (lower-case `https://host`, the port only when it isn't 443, no path, query or fragment) or `null` for an address another device can't use (not HTTPS, user information, no host, no scheme).
- `scannedTexts`: what reading scanned text concludes: `invite` (with the server address as written), `notInvite` (keep scanning: not the `MYJOURNAL1.` prefix, not base64url, or a payload of 80 bytes or fewer), `newerVersion` (`MYJOURNAL` and another digit) or `unreachableServer` (a well-formed code whose address isn't an HTTPS origin).
- `checkCodes`: for a pairing ID and two public keys, the key `commitment` (base64 of SHA-256 of `journal:v2:pairing-commitment` and the key), the `checkCode` and how it is `shown`. The pairing ID is hashed in lower case, so an upper-case ID gives the same code. One entry has leading zeros; one is the protocol README's vector (keys of 0x07 and 0x09, code 479111).

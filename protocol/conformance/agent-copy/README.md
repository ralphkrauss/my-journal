# agent-copy

Agent access through the server ([agent-access-server.md](../../agent-access-server.md)).

| File | Covers | Produced by |
| --- | --- | --- |
| `agent-copy-v1.json` | Copy subkeys, an item ID, digest and sealed item, and a copy key wrap, with two wrong positions that must fail | .NET 10 |

## Contents

- `encryptionKey` and `itemIdKey` = HKDF-SHA256(`copyKey`, no salt, info `journal:v1:agent-copy:encryption` / `journal:v1:agent-copy:item-id`, 32 bytes).
- `item.itemId` = lowercase hex of the first 16 bytes of HMAC-SHA256(`itemIdKey`, `journal:v1:agent-item:{recordId}`); `item.digest` likewise over `journal:v1:agent-digest:` ‖ `plaintext`. `item.combined` seals `plaintext` under `encryptionKey` with `item.context` (`journal:v1:agent-copy:{grantId}:{itemId}`). Each `negative` context must fail to open it.
- `wrap.wrappedKey` seals `copyKey` under HKDF-SHA256(`wrap.secret`, no salt, info `journal:v1:agent-grant-wrap`, 32 bytes) with `wrap.context` (`journal:v1:agent-grant:{grantId}`). A token's wrap uses the same construction with info `journal:v1:agent-token-wrap`.

`AgentAccessTests` checks the file with .NET; Swift `AgentCopyTests` checks it through the app's own sealing and wrapping code.

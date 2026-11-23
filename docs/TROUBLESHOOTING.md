# Troubleshooting

When something fails, open **Settings › Logs** (the gear at the top right) and tap **Copy**, or tap **Copy Log** on the error screen. Paste it into an [issue](https://github.com/mirazbakis/AltLoad/issues). Emails are masked, and passwords, codes, tokens and pairing files are never logged.

## Connecting to this iPhone

### "Can't connect to this iPhone" or "Connection refused"

- LocalDevVPN must be connected, and no other VPN or proxy app on. iOS runs one VPN at a time.
- Developer Mode must be on.
- This iPhone must be paired in **Tools › Pair**.
- Allow Local Network access if AltLoad asks. AltLoad uses it to find the port the pairing service is on.

If it still fails, turn LocalDevVPN off and on, or pair again.

### "Couldn't open a tunnel to this device after 3 tries"

The pairing service answered, but the connection after it stalled. This mostly happens right after LocalDevVPN connects.

- Turn LocalDevVPN off and on, wait a few seconds, and try again.
- Update AltLoad. Since 1.8.0, AltLoad sets up one connection to the iPhone at a time, so an install and the JIT tab no longer stall each other.

### "This iPhone no longer accepts the pairing file"

The iPhone no longer trusts the saved pairing, for example after resetting its settings. Pair again in **Tools › Pair**.

## Signing in

### Sign-in fails

Leave **Settings › Anisette** on **Automatic**. If sign-in still fails, tap **Reset Anisette Data** and try again a few minutes later.

### "Sign-ins are paused"

After two wrong passwords in a row, a locked account, or Apple's "too many requests", AltLoad pauses sign-ins for that Apple ID for a while so Apple doesn't lock it. Wait for the time AltLoad shows.

## Installing

### "Not enough available App IDs"

A free Apple ID can create 10 App IDs a week, and each app extension normally needs one. On the install screen, before you sign in, set **App Extensions** to **Keep, Use Main Profile** or **Remove Extensions**. **Tools › App IDs** shows which are in use and when they free up.

### "Certificate limit reached"

Free Apple IDs get only a few development certificates. AltLoad asks which one to revoke. Apps signed with it elsewhere stop opening until they're signed again.

### A store won't download

If a store's sources are all down, AltLoad uses the copy it downloaded last time. With no copy, get the IPA another way and use **Install IPA from Files** in the Install tab's **…** menu.

### An app from a source won't download

- "The download wasn't an IPA": the source's link leads to a web page, not the file. Tell the source's owner.
- "The source returned HTTP 404": the file was moved or removed. Pull down on Sources to read the source again.

See [Sources](SOURCES.md) for how sources work.

### The app closes as soon as it opens

Trust your Apple ID in **Settings › General › VPN & Device Management**. If it still closes, the signature may have expired: refresh it in AltLoad.

## Installing AltLoad with an Apple ID (rootshell and Open Minis)

### `wasm: command not found`

rootshell can't pipe into a `.wasm` program. Save `ifconfig en0` to a file and read it with `<`, as the steps on [altload.org](https://altload.org/apple-id.html) show.

### It stays at "Reading ifconfig from stdin..."

Older copies of the pairing tool wait for rootshell to finish sending `if.txt`, which doesn't always happen. Press Ctrl-C, download the tool again with the `curl` line, and run it again: it now reads `if.txt` by itself. Or skip the file and give the address directly: `./altpair.wasm --ip A.B.C.D` (your Wi-Fi address from Settings › Wi-Fi › ⓘ).

### **Pair with AltLoad** doesn't appear

Check Developer Mode is on and the iPhone is on Wi-Fi. The pairing tool needs rootshell 1.0.16-177 or later.

### `Protocol not available (os error 92)`

Your copy of the installer is older than the fix for Open Minis. Run the install line again: it downloads the latest one.

### "LocalDevVPN isn't connected"

Open LocalDevVPN and tap Connect, then run `altpair` again. If it is connected, add `--verbose` and include the output in an issue.

More detail is in [altpair/README.md](../altpair/README.md).

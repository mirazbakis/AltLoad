# FAQ

### Is my Apple ID password safe?

Your password goes to Apple only. AltLoad keeps it in the iPhone's Keychain if you choose to save it, so automatic refresh can sign apps again. The anisette server AltLoad uses for sign-in never sees it. Download AltLoad only from [altload.org](https://altload.org/) or this repository: a copy from anywhere else could be modified to steal it.

### Do I need a computer?

On iOS 27 and later, no. AltLoad pairs the iPhone with itself. On iOS 18 to 26, you make one pairing file on a computer with [iloader](https://github.com/nab138/iloader) or [idevice_pair](https://github.com/jkcoxson/idevice_pair) and import it in **Tools › Pair**. After that, everything happens on the iPhone.

### Why does it need LocalDevVPN?

An app can't connect to its own iPhone's device services directly. LocalDevVPN reflects packets for one private address back to the iPhone, so the connection looks like it came from another machine. Only that address goes through it, not your other traffic. See [How it works](HOW-IT-WORKS.md#2-tunnel-to-this-iphone-install-step-1).

### How long do apps last?

With a free Apple ID, 7 days. AltLoad refreshes apps before they expire if automatic refresh is on, LocalDevVPN is connected and the password is saved. With a paid developer account, a year.

### How many apps can I install?

A free Apple ID allows 3 sideloaded apps at once (AltLoad counts if your Apple ID signed it) and 10 App IDs a week. A paid account has no app limit.

### Can Apple revoke it?

Apps signed with your own Apple ID use your own certificate, so nobody else can revoke it. You can revoke it yourself, and AltLoad asks before it does when the certificate limit is reached. The Direct Install route on the website uses a shared certificate, which can be revoked.

### What's the difference between AltLoad and AltStore or SideStore?

AltStore and SideStore are app stores that need something to sign and refresh them: a computer running AltServer, or a pairing file and a VPN. AltLoad is that something, on the iPhone itself. It installs the store for you, then acts as AltServer so AltStore can refresh. It can also install apps directly, from Files or from a [source](SOURCES.md).

### Can I install apps without a store?

Yes. Use **Install IPA from Files** or **Sources** in the Install tab's **…** menu.

### Does AltLoad collect data?

No analytics. AltLoad talks to Apple to sign in and sign apps, to an anisette server for sign-in headers, to the stores' sources and GitHub to download apps, and to GitHub to check for its own updates. Logs stay on the iPhone until you share them.

### Something doesn't work

See [Troubleshooting](TROUBLESHOOTING.md).

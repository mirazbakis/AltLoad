# Security Policy

AltLoad handles sensitive things: your Apple ID sign-in, a development certificate, and pairing files that grant access to your iPhone. Please report security problems privately so they can be fixed before they're public.

## Supported versions

| Version | Supported |
|---|---|
| Latest release and the `main` branch | ✅ |
| Older releases | ❌ Please update first |

## Reporting a vulnerability

**Please don't open a public issue for security problems.**

1. Go to this repository's **[Security › Report a vulnerability](https://github.com/mirazbakis/AltLoad/security/advisories/new)** page. This creates a private report that only the maintainers can see.
2. Include:
   - what the problem is and where (file, screen or step),
   - how to reproduce it,
   - what an attacker could do with it,
   - your AltLoad version or commit, iOS version and device.

**What happens next:**

- You'll get an acknowledgement within **7 days**.
- We'll confirm the issue and agree on a fix and disclosure timeline with you. The aim is a fix within **90 days**, sooner for serious issues.
- Once a fix is released, the advisory is published. You'll be credited unless you'd rather not be.

## Scope

**In scope:** code in this repository, including:

- handling of Apple ID credentials and 2FA (`App/AppleIDStore.swift`, `App/InstallSheets.swift`, `rust/src/install.rs`),
- storage and handling of pairing files, certificates and private keys,
- the tunnel to the device and the install pipeline,
- how AltLoad talks to anisette servers, the AltStore source and LocalDevVPN,
- the build workflow in `.github/workflows/`.

**Out of scope** (please report these to the right project):

- [AltStore](https://github.com/altstoreio/AltStore)
- [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN)
- [idevice](https://github.com/jkcoxson/idevice) and [isideload](https://github.com/nab138/isideload), unless the problem is in how AltLoad uses them
- anisette servers run by third parties
- Apple's services and iOS itself
- problems that need an already-jailbroken or already-compromised device

## Safe harbor

We won't pursue or support legal action against anyone who researches and reports in good faith: someone who follows this policy, avoids privacy violations, data destruction and service disruption, only tests with their own devices and accounts, and gives us reasonable time to fix the problem before disclosing it.

## How AltLoad protects your data

- **Apple ID password:** sent only to Apple's sign-in servers (GrandSlam, using the SRP protocol, so the password itself isn't transmitted). It's saved only if you turn on *Remember password*, and then only in the iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: readable only while unlocked, and never synced or backed up to other devices.
- **Anisette server:** receives device-identity data needed for Apple sign-in, **never** your password. You can choose the server or run your own.
- **Development certificate and key:** stored in the Keychain.
- **Pairing files:** stored in the app's Documents folder. Anyone with a pairing file can connect to your device, so share them only with apps you trust.
- **Connections to the device:** go through an encrypted TLS-PSK tunnel that only a valid pairing file can open.
- **No tracking:** AltLoad has no analytics or telemetry and doesn't send data to the AltLoad developers.
- **Repository:** `.gitignore` blocks certificates, keys, provisioning profiles, `.env` files and pairing files from being committed. CI builds are unsigned and use no secrets.

## Tips for users

- Download AltLoad only from this repository's [Releases](https://github.com/mirazbakis/AltLoad/releases) or [Actions](https://github.com/mirazbakis/AltLoad/actions), or build it yourself.
- Consider using a secondary Apple ID for sideloading.
- Never share your pairing files, `.p12` certificates or Apple ID password.
- Turn LocalDevVPN off when you're not installing or refreshing.

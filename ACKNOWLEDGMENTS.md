# Acknowledgments

AltLoad exists because of the work of these people and projects. Thank you.

## Core

- **[Jackson Coxson (jkcoxson)](https://github.com/jkcoxson):** [idevice](https://github.com/jkcoxson/idevice), [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN), [idevice_pair](https://github.com/jkcoxson/idevice_pair) and public anisette servers. These connect the iPhone to itself.
- **[nab138](https://github.com/nab138):** [isideload](https://github.com/nab138/isideload), which handles Apple ID sign-in and code signing, and [iloader](https://github.com/nab138/iloader), whose pairing file locations AltLoad follows.
- **[StephenDev0](https://github.com/StephenDev0):** [StikPair](https://github.com/StephenDev0/StikPair) and [StikDebug](https://github.com/StephenDev0/StikDebug), for pairing and JIT.
- **[StikDebug project](https://github.com/StikDebug/StikDebug):** the JIT request protocol that emulators use to ask a debugger for JIT memory. AltLoad's debugger side speaks it with its own implementation; no StikDebug code is used.

## Apps AltLoad installs

- **[Riley Testut](https://github.com/rileytestut):** [AltStore](https://altstore.io) and the AltServer protocol.
- **[SideStore Team](https://github.com/SideStore):** SideStore and its public anisette servers.
- **[LiveContainer](https://github.com/LiveContainer/LiveContainer):** running apps without installing them.
- **[Leviidev](https://github.com/Leviidev):** [Husk](https://github.com/Leviidev/Husk), Android apps and games on iPhone.
- **[UTM](https://github.com/utmapp/UTM):** virtual machines on iPhone.
- **[MeloNX](https://starforgejo.dev/projects/MeloNX):** Nintendo Switch emulator.
- **[willfaust](https://github.com/willfaust):** [Madeira](https://github.com/willfaust/Madeira), Windows PC games on iPhone.

## Services and resources

- **[Kit Knox / Rootshell LLC](https://github.com/kitknox/rootshell):** rootshell, the App Store terminal. Its MIT-licensed WASM interface is what `altpair.wasm` is written against. AltLoad includes no rootshell code.
- **Open Minis:** the App Store app that altpair's installer, `altpair`, runs in. AltLoad includes no Open Minis code.
- **[WSF Team](https://github.com/WhySooooFurious):** the madNS DNS server used by AltLoad's DNS profile.
- **Anisette server hosts:** nythepegasus, WE. Studio and crystall1nedev, along with the hosts above.
- **[doronz88](https://github.com/doronz88):** [DeveloperDiskImage](https://github.com/doronz88/DeveloperDiskImage), which AltLoad downloads for JIT and location simulation.
- **[AltDirect](https://altdirect.app):** the source and download buttons in the README.

Listing a project here doesn't mean it endorses or is affiliated with AltLoad. Licenses for bundled code are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

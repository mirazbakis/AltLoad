# Sources

A source is a JSON file that lists apps and their versions, in the format AltStore and SideStore use. Add one to AltLoad, and you can browse its apps and install or update them without downloading IPAs by hand.

## Using sources

1. Open the **Install** tab, tap **…** at the top left, then **Sources**.
2. Paste a source link and tap **Add Source**. AltLoad accepts:
   - an https link, such as `https://apps.sidestore.io`
   - a link without `https://`, such as `apps.altstore.io`
   - an add-source link, such as `altstore://source?url=https://…` or `sidestore://source?url=https://…`

   AltLoad reads the link before saving it, so only a working source is kept. AltStore, SideStore and Husk are suggested under the field, one tap each.
3. Tap an app to see what's new in it, its description and older versions. Tap **Install**.

Installing downloads the IPA, then runs the same steps as **Install IPA from Files**: LocalDevVPN, your Apple ID, signing and installing. Apps from a source show up in **Your Apps** on the Install tab and refresh like any other app.

### Updates

When a source lists a newer version of an app AltLoad installed, the app shows **Update**, both in Sources and in **Your Apps**. Sources are read when AltLoad opens. Pull down on the Sources page to read them again.

AltLoad matches an installed app to a source by bundle ID. Signing can add your team ID to the end of it (`com.example.app.ABCDE12345`), and AltLoad accounts for that. Versions are compared number by number, so `1.10` is newer than `1.9`, and `1.2` is the same as `1.2.0`.

### Older versions

An app's page lists every version the source has. Installing an older one asks first, because an older version may not open data saved by a newer one.

### Removing a source

Under **Your Sources**, tap the trash button. Apps you installed from it stay installed and keep refreshing from the IPA AltLoad saved. They just won't show updates any more.

## What AltLoad reads from a source

Source authors: AltLoad reads the common AltStore source fields and ignores the rest. One broken app or version doesn't hide the others.

```json
{
  "name": "Example Source",
  "iconURL": "https://example.com/icon.png",
  "apps": [
    {
      "name": "Example",
      "bundleIdentifier": "com.example.app",
      "developerName": "Example Developer",
      "subtitle": "One line about the app",
      "localizedDescription": "A longer description. **Markdown** works.",
      "iconURL": "https://example.com/app.png",
      "versions": [
        {
          "version": "1.2",
          "date": "2026-11-20",
          "downloadURL": "https://example.com/Example-1.2.ipa",
          "size": 12345678,
          "minOSVersion": "17.0",
          "localizedDescription": "What's new in 1.2"
        }
      ]
    }
  ]
}
```

| Field | Needed | Notes |
| :-- | :-- | :-- |
| `apps[].bundleIdentifier` | Yes | Used to match installed apps |
| `apps[].versions[].version` | Yes | |
| `apps[].versions[].downloadURL` | Yes | Must download the IPA itself, not a web page. AltLoad checks the file is a zip |
| `apps[].versions` | | Newest first. Older sources that put `version`, `versionDate`, `downloadURL` and `versionDescription` on the app itself work too |
| `minOSVersion` | | AltLoad warns when the iPhone is older |
| `localizedDescription` | | Shown as Markdown |

AltLoad doesn't read `news`, `featuredApps`, `permissions` or `appPermissions`. Entitlements come from the IPA and from **Tools › Entitlements**.

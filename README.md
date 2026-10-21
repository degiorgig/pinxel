# Pinxel

Native screen capture and annotation editor for macOS (SwiftUI + AppKit).

## What it does

- **Capture:** an area, a window (with or without its shadow), the full screen, the last area again, and scrolling capture (you scroll, Pinxel stitches).
- **After capture:** open the editor, a quick preview, or copy to the clipboard only. Every capture also goes into the library.
- **Editor:**
  - **Tools:** arrows, lines, shapes, text, callouts, numbered steps, pen, highlighter, blur and pixelate, magnifier.
  - **Image:** crop, cut out a band, resize, border, shadow and padding.
  - **Objects:** the capture and any dropped image are ordinary objects. Move them, rotate them, bring them forward or send them back; the canvas always fits the content.
  - **Conveniences:** quick styles, smart guides, locked objects, undo and redo.
- **Library:** every capture in `~/Pictures/Pinxel/Library`, with a strip under the editor (⌃⌘L), folders, tags and search.
- **Export:** PNG, JPEG, HEIC and PDF. You can also share the capture or drag it into another app.
- **Format:** `.pinxel` documents keep editable annotations and the original images.
- **Languages:** English, Italian, German and French (follows the Mac's language).

## Default shortcuts

| Shortcut | Action |
|---|---|
| ⌃⇧1 | Capture an area |
| ⌃⇧2 | Capture a window |
| ⌃⇧3 | Capture the full screen |
| ⌃⇧4 | Repeat the last area |
| ⌃⇧5 | Scrolling capture |

You can change them in Settings. In the editor every tool has its own letter (hover over a tool to see it).

## Requirements

- macOS 15 or later (Apple Silicon and Intel).
- **Screen Recording** permission (System Settings ▸ Privacy & Security), requested on first launch.

## Install

Download `Pinxel-<version>.dmg` or `.zip` from the [releases](https://github.com/degiorgig/pinxel/releases) and drag Pinxel into Applications.

From 0.3.0 the builds are signed with Developer ID and notarized by Apple, so they open normally on any Mac. Versions 0.1.0 and 0.2.0 are not notarized: macOS blocks them on first launch; open them with right-click ▸ Open, or from System Settings ▸ Privacy & Security ▸ Open Anyway.

## Building from source

You need Xcode (tested with Xcode 27) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open Pinxel.xcodeproj
```

Without further setup the app is signed ad hoc, and macOS asks for the Screen Recording permission again after every build. For a stable signature create `App/Config/Signing.local.xcconfig` (ignored by git) with your certificate:

```
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = <your team ID>
```

Package tests: `cd PinxelKit && swift test`.

## Releasing

Every pull request runs the package tests, builds the app and the UI tests, and checks that every string has a translation (`.github/workflows/ci.yml`).

To publish version X.Y.Z:

1. In a pull request, set `MARKETING_VERSION` to `X.Y.Z` (and bump `CURRENT_PROJECT_VERSION`) in `project.yml`, and add the release notes as `docs/releases/X.Y.Z.md`.
2. After merging, tag `main` and push the tag:

   ```sh
   git tag -a vX.Y.Z -m "Pinxel X.Y.Z" && git push origin vX.Y.Z
   ```

The `Release` workflow then runs the tests, builds the app, signs it with Developer ID, has Apple notarize it, creates `Pinxel-X.Y.Z.dmg` and `Pinxel-X.Y.Z.zip`, and publishes the GitHub release with the notes and the SHA-256 checksums. `scripts/release/package.sh X.Y.Z` does the same packaging locally (see the comment at the top of the script for the notarization credentials).

Running the `Release` workflow by hand (Actions ▸ Release ▸ Run workflow, or `gh workflow run Release`) is a dry run: it builds, signs and notarizes the version in `project.yml` and keeps the dmg and zip as a workflow artifact for 7 days, without publishing anything.

The workflow signs with a Developer ID Application certificate, so the app opens on any Mac and the Screen Recording permission survives updates. It needs these repository settings:

| Name | Kind | Value |
|------|------|-------|
| `MACOS_CERTIFICATE_P12` | secret | the Developer ID Application certificate with its private key, exported as `.p12` and base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | secret | the `.p12` password |
| `NOTARY_APPLE_ID` | secret | the Apple ID of the developer account |
| `NOTARY_PASSWORD` | secret | an [app-specific password](https://support.apple.com/102654) of that Apple ID |
| `DEVELOPMENT_TEAM` | variable | the team ID of the certificate |

### Mac App Store

The `AppStore` build configuration is the sandboxed version for the Mac App Store, signed with Apple Distribution and the Mac App Store provisioning profile. `scripts/release/appstore.sh X.Y.Z` archives it and exports `Pinxel.pkg` (with `UPLOAD=1`, it uploads it to App Store Connect). The `app-store` job of the `Release` workflow does the same on every tag, once its secrets are set; the one-time setup is in [docs/app-store/setup.md](docs/app-store/setup.md) (in Italian), and the store texts in [docs/app-store/listing.md](docs/app-store/listing.md).

## Privacy

Pinxel collects no data and does not connect to the internet: see [PRIVACY.md](PRIVACY.md).

## License

Pinxel is free for personal, non-commercial use: you may download, use and build it at no cost for private purposes.

Use by companies, organizations or for any commercial purpose — including use by employees on the job — requires a paid commercial license. To obtain one, contact the author through [GitHub](https://github.com/degiorgig).

Redistribution of the app or of modified versions is not permitted without the author's written consent. The software is provided "as is", without warranty of any kind. See [LICENSE](LICENSE) for the full terms.

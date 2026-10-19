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
- **Library:** every capture in `~/Pictures/Pinxel/Libreria`, with a strip under the editor (⌃⌘L), folders, tags and search.
- **Export:** PNG, JPEG, HEIC and PDF. You can also share the capture or drag it into another app.
- **Format:** `.pinxel` documents keep editable annotations and the original images.

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

Published builds are not notarized by Apple. On a Mac other than the one that signed them, macOS blocks them on first launch: open the app with right-click ▸ Open, or from System Settings ▸ Privacy & Security ▸ Open Anyway.

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

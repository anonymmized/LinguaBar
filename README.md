# LinguaBar

LinguaBar is a lightweight macOS menu bar translator built with Swift and AppKit.

It stays in the macOS status bar, opens as a compact floating translator panel, and can be shown or hidden instantly with a global hotkey.

## Features

- macOS menu bar app with no Dock icon
- Compact HUD-style translator window
- Global shortcut: `Command + Option + T`
- Auto-hide when switching to another app
- Native macOS window controls
- Custom menu bar logo
- Secondary click menu with settings and quit
- Settings for launch behavior, auto-hide, and auto-translation
- Translation between:
  - Russian
  - English
  - French
  - Italian
  - Spanish
- Auto-translation after typing
- Language swap
- Copy translated text
- Tiny app bundle, around a few hundred KB

## Preview

LinguaBar is designed to behave like a small system utility: open it, translate, and let it disappear when you continue working elsewhere.

## Requirements

- macOS 13 or newer
- Swift 6 toolchain or recent Xcode Command Line Tools

## Build

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

The app bundle will be created at:

```text
build/LinguaBar.app
```

## Run

```bash
open build/LinguaBar.app
```

After launch, LinguaBar appears in the top menu bar. Press `Command + Option + T` to show or hide the translator window.

Secondary click the menu bar icon to open the menu:

- open or hide the translator
- open settings
- quit LinguaBar completely

## Project Structure

```text
.
├── Package.swift
├── Resources
│   └── Info.plist
├── Sources
│   └── LinguaBar
│       └── main.swift
└── scripts
    └── build_app.sh
```

## Notes

LinguaBar uses the MyMemory translation endpoint for online translation and includes a small local phrasebook fallback for common phrases.

The app is ad-hoc signed during local builds. For public distribution outside your own machine, use a proper Apple Developer ID certificate and notarization.

## License

MIT

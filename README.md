<p align="center">
  <img src="README.assets/icon.png" width="132" alt="LinguaBar app icon">
</p>

<h1 align="center">LinguaBar</h1>

<p align="center">
  A tiny, elegant translator that lives in your macOS menu bar.
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-111111?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-FA7343?style=for-the-badge&logo=swift&logoColor=white">
  <img alt="AppKit" src="https://img.shields.io/badge/AppKit-native-FF4F63?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-2C2D31?style=for-the-badge">
</p>

<p align="center">
  <img src="README.assets/preview.svg" alt="LinguaBar preview">
</p>

## Why LinguaBar

LinguaBar is built for quick translation without opening a browser tab. It stays out of the Dock, sits in the macOS menu bar, and opens as a compact HUD-style panel when you need it.

## Features

- Lives in the macOS menu bar
- Opens and hides with `Command + Option + T`
- Auto-hides when you switch to another app
- Secondary click menu for settings and quit
- Native macOS window controls
- Custom Finder, Spotlight, and menu bar icon
- Compact blur/HUD interface
- Auto-translation while typing
- Language swap and copy action
- Translation between Russian, English, French, Italian, and Spanish
- MyMemory online translation with a small local phrasebook fallback

## Install For Finder And Spotlight

Build, sign, install into `/Applications`, and open LinguaBar:

<p>
  <img src="README.assets/install-card.svg" alt="Install LinguaBar command">
</p>

After installation, macOS can open it from:

- Finder: `/Applications/LinguaBar.app`
- Spotlight: search `LinguaBar`
- Terminal:

<p>
  <img src="README.assets/open-card.svg" alt="Open LinguaBar from Applications">
</p>

If Spotlight does not show it immediately, wait a minute for indexing or run:

<p>
  <img src="README.assets/spotlight-card.svg" alt="Index LinguaBar with Spotlight">
</p>

## Build Only

<p>
  <img src="README.assets/build-card.svg" alt="Build LinguaBar command">
</p>

The app bundle will be created at:

<p>
  <img src="README.assets/output-card.svg" alt="LinguaBar build output path">
</p>

## Usage

Press `Command + Option + T` to show or hide the translator window.

Secondary click the menu bar icon to open the menu:

- open or hide the translator
- open settings
- quit LinguaBar completely

## Settings

LinguaBar includes a compact settings panel for:

- showing the translator on launch
- hiding the translator when another app is selected
- automatic translation while typing

## Project Structure

<p>
  <img src="README.assets/structure.svg" alt="LinguaBar project structure">
</p>

## Distribution Note

Local builds are ad-hoc signed. That is enough for personal use, Finder, and Spotlight installation on your own Mac. For public distribution, sign with an Apple Developer ID certificate and notarize the app.

## License

MIT

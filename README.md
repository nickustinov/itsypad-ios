# Itsypad for iOS

[![Tests](https://github.com/nickustinov/itsypad-ios/actions/workflows/tests.yml/badge.svg)](https://github.com/nickustinov/itsypad-ios/actions/workflows/tests.yml)
[![Release](https://img.shields.io/github/v/release/nickustinov/itsypad-ios)](https://github.com/nickustinov/itsypad-ios/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift 5.9](https://img.shields.io/badge/swift-5.9-orange.svg)](https://swift.org)
[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-brightgreen.svg)](https://www.apple.com/ios/)

The iOS companion to [Itsypad](https://itsypad.app) – a tiny, fast scratchpad and clipboard manager. Syncs your scratch tabs and clipboard history across all your devices via iCloud.

## Features

- Multi-tab scratchpad with session persistence
- Clipboard history (up to 1,000 entries) with search
- iCloud sync with the macOS version (last-modified-wins conflict resolution)
- Syntax highlighting via highlight.js (26+ languages)
- 9 colour themes with light/dark variants
- Bullet lists, numbered lists, and checklists with auto-continuation
- Checkbox tap-to-toggle
- Tab grid expose view
- Configurable indentation (spaces/tabs, width)
- Auto-language detection
- Hardware keyboard support on iPad (Cmd+D duplicate line, Cmd+Return toggle checkbox, Cmd+Shift+L toggle checklist, Cmd+S save, Cmd+Shift+S save as)
- 12 languages: English, Spanish, French, German, Russian, Japanese, Simplified Chinese, Traditional Chinese, Korean, Portuguese (Brazil), Italian, Polish

## Requirements

- iOS 17.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation

## Setup

```bash
xcodegen generate
open itsypad-ios.xcodeproj
```

## Localization

Itsypad uses a Swift String Catalog (`Sources/Resources/Localizable.xcstrings`) for localization. Translations are managed via [Lokalise](https://lokalise.com).

Languages: English (base), Spanish, French, German, Russian, Japanese, Simplified Chinese, Traditional Chinese, Korean, Portuguese (Brazil), Italian, Polish.

### Setup

```bash
brew tap lokalise/cli-2
brew install lokalise2
cp lokalise.yml.example lokalise.yml
# Edit lokalise.yml and add your API token
```

### Push source strings to Lokalise

Extracts English keys and values from the xcstrings file and uploads to Lokalise:

```bash
scripts/push-translations.sh
```

### Pull translations from Lokalise

Downloads all translations from Lokalise and merges them into the xcstrings file:

```bash
scripts/pull-translations.sh
```

### Adding new strings

All user-facing strings use `String(localized:defaultValue:)` with a structured key:

```swift
Toggle(String(localized: "settings.appearance.word_wrap", defaultValue: "Word wrap"), isOn: $store.wordWrap)
Section(String(localized: "settings.spacing.title", defaultValue: "Spacing")) { ... }
```

Key format: `{area}.{context}.{name}` – e.g. `menu.file.*`, `alert.save_changes.*`, `settings.appearance.*`, `clipboard.*`, `tab.context.*`.

### Workflow after adding new strings

1. Build the project – Xcode auto-populates new keys in `Localizable.xcstrings`
2. Push source strings to Lokalise: `scripts/push-translations.sh`
3. Translate in [Lokalise](https://app.lokalise.com) (or let translators handle it)
4. Pull translations back: `scripts/pull-translations.sh`
5. Build and verify

## Architecture

SwiftUI + UIKit hybrid. SwiftUI handles navigation and settings, UIKit's UITextView powers the editor for full control over text input, syntax highlighting, and keyboard interaction.

| Module | Purpose |
|--------|---------|
| `App/` | App entry, main layout, tab store |
| `Editor/` | Text editor, syntax highlighting, list handling |
| `Settings/` | Settings UI and persistence |
| `TabGrid/` | Tab grid expose view |
| `Clipboard/` | Clipboard history and iCloud sync |

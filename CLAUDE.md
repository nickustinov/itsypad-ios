# Itsypad

iOS scratchpad and clipboard manager. Swift, UIKit, SwiftUI.

## Build

```bash
xcodegen generate
xcodebuild -scheme Itsypad -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme Itsypad -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Always run `xcodegen generate` after changing `project.yml` or adding/removing source files.

## Project structure

- `Sources/` – app code (App, Editor, Clipboard, Settings, TabGrid, Resources)
- `Tests/` – unit tests
- `scripts/` – translation scripts
- `project.yml` – XcodeGen project definition

## Localization

All user-facing strings use `String(localized:defaultValue:)` with structured keys:

```swift
String(localized: "menu.file.new_tab", defaultValue: "New tab")
```

Key format: `{area}.{context}.{name}` – e.g. `menu.file.*`, `alert.save_changes.*`, `settings.appearance.*`, `clipboard.*`, `tab.context.*`.

After adding new strings:
1. Build (Xcode populates `Sources/Resources/Localizable.xcstrings`)
2. `scripts/push-translations.sh` (push English to Lokalise)
3. Translate in Lokalise
4. `scripts/pull-translations.sh` (pull translations back)

Lokalise config: `lokalise.yml` (gitignored). Copy from `lokalise.yml.example`.

## Conventions

- Version in `project.yml`: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
- European-style titles, not American Title Case
- En dashes (–), not em dashes (—)

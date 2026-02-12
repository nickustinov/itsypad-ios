# Itsypad for iOS

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

## Requirements

- iOS 17.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation

## Setup

```bash
xcodegen generate
open itsypad-ios.xcodeproj
```

## Architecture

SwiftUI + UIKit hybrid. SwiftUI handles navigation and settings, UIKit's UITextView powers the editor for full control over text input, syntax highlighting, and keyboard interaction.

| Module | Purpose |
|--------|---------|
| `App/` | App entry, main layout, tab store |
| `Editor/` | Text editor, syntax highlighting, list handling |
| `Settings/` | Settings UI and persistence |
| `TabGrid/` | Tab grid expose view |
| `Clipboard/` | Clipboard history and iCloud sync |

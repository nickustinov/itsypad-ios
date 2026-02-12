# Itsypad for iOS

A lightweight code editor for iPhone and iPad with syntax highlighting, list support, and iCloud sync.

## Features

- Syntax highlighting via highlight.js (26+ languages)
- 9 colour themes with light/dark variants
- Bullet lists, numbered lists, and checklists with auto-continuation
- Checkbox tap-to-toggle
- Tab management with grid expose view
- iCloud sync with the macOS version (last-modified-wins conflict resolution)
- Hardware keyboard shortcuts (Cmd+D duplicate, Cmd+Return toggle checkbox, Cmd+Shift+L toggle checklist)
- Configurable indentation (spaces/tabs, width)
- Auto-language detection

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

# Changelog

## 1.2.0

- Fix cursor jumping to the end of the text when iCloud sync applies changes from another device
- Fix text and cursor hidden under the keyboard after switching tabs while the keyboard is open
- Fix iCloud sync not receiving remote changes until relaunch (missing push notification registration)
- Fix iCloud sync conflict resolution re-uploading stale content and reverting newer edits from other devices
- Fix blank editor when another device deletes the currently open tab
- Fix sync engine data races and slow per-record metadata writes
- Fix closing an unsaved tab via "Save" exporting the wrong tab's content and losing the closed tab
- Fix saving to files imported from the Files app silently failing (security-scoped bookmarks)
- Show an alert when saving a file fails instead of failing silently
- Back up an unreadable session file instead of overwriting it with an empty session
- Flush clipboard history to disk when the app is backgrounded
- Fix text corruption and cursor misplacement in list/indent operations on lines with emoji
- Fix undo after list toggles, indent, and duplicate line deleting the wrong characters
- Fix memory leak in syntax highlighting (one full-document copy per keystroke)
- Fix scroll position jumping back to the cursor after delayed highlighting
- Fix cloud sync destroying in-progress CJK/IME text composition
- Fix "Lock rotation" toggle not taking effect until the next rotation event
- Persist and sync auto-detected language immediately instead of after the next edit
- Localize auto-generated "Untitled" tab names
- Add edge swipe gestures to switch between tabs
- Fix keyboard staying dismissed after launching the app on iPad
- Enable auto-capitalization after sentence punctuation for plain text and markdown tabs
- Enable word suggestions and spell checking for plain text and markdown tabs

## 1.1.0

- Add bullet list and numbered list toggles to the file menu and text selection edit menu
- Add keyboard shortcuts for bullet list (Cmd+Shift+B) and numbered list (Cmd+Shift+N)
- Add community link to settings
- Add localization for 12 languages (Spanish, French, German, Russian, Japanese, Simplified Chinese, Traditional Chinese, Korean, Portuguese Brazil, Italian, Polish)
- Add "Toggle checklist" to text selection context menu
- Add "Lock rotation" setting for iPhone (enabled by default)
- Fix list toggles not inserting prefix on empty last line without trailing newline
- Fix editor not responding to taps after returning from background
- Add word wrap setting (default: on) with horizontal scrolling when off
- Add line numbers setting with gutter view
- Move toolbar buttons to floating bottom bar with Liquid Glass support
- Remove navigation bar title for cleaner editor view
- Make editor extend under navigation and toolbar bars for transparency
- Add line spacing and letter spacing settings to the editor
- Add Solarized syntax theme
- Update welcome tab content

# Kipple


[Japanese README](README.ja.md)

![Kipple icon](https://github.com/user-attachments/assets/2c295e8a-2fcd-4102-8e46-75bcbaaa79d9)

Kipple is a local-first clipboard manager for macOS.

It keeps your copied text searchable, editable, organized, and ready to paste again. It is built for people who copy lots of text while writing, researching, coding, filling forms, or moving information between apps.

[Download the latest release](https://github.com/nissy/kipple/releases/latest/download/Kipple.dmg)

<img width="755" height="775" src="https://github.com/user-attachments/assets/4c4e2b1f-8055-43d8-82f6-25496d6975df" alt="Kipple main window" />

## Why Kipple?

Kipple is more than a clipboard history list.

- Search copied text and bring it back instantly
- Pin important clips so they stay available
- Edit clipboard text in the Live Editor before saving or pasting
- Format JSON and YAML directly from the editor
- Paste multiple clips in order with Queue
- Capture text from the screen with OCR
- Keep clipboard history on your Mac

## Features

### Clipboard History

Kipple automatically saves copied text and shows it in a compact menu bar window. Selecting an item copies it back to the clipboard.

History items can include:

- copied text
- copied time
- source app
- source window title
- URL classification
- pin state
- user category

Duplicate copies are moved to the top instead of creating another identical item.

### Search, Pin, and Categories

Search across clipboard content and source app names. Pin items that should stay available, and organize clips with built-in or custom categories.

Kipple includes built-in `None` and `URL` categories. You can also add your own categories with names and SF Symbol icons.

### Live Editor

The Live Editor lets you inspect and edit the current clipboard text before saving it to history.

You can:

- edit the current clipboard text
- save edited text to history
- trim surrounding whitespace and newlines
- format JSON
- format YAML

### Queue Paste

Queue lets you paste multiple history items in a chosen order.

Turn on Queue, select clips from history, then press `Command + V` repeatedly. Kipple advances to the next queued item after each paste. Loop mode can repeat the queue.

Queue is useful for forms, repetitive data entry, and moving several values between apps without copying each item manually.

### Screen Text Capture

Screen Text Capture lets you select an area of the screen and extract text with macOS Vision OCR.

Recognized text is copied to the clipboard and saved to history. OCR processing happens on your Mac.

### Paste on Selection

Paste on Selection can paste a selected history item directly into the previously active app. This is useful when you want one-click selection and paste behavior.

## Privacy

Kipple is local-first.

- Clipboard history stays on your Mac
- Settings are stored locally
- Categories are stored locally
- OCR runs on device
- No analytics
- No tracking
- No cloud sync

Kipple does not send your clipboard history to external services.

## Installation

1. Download the latest release from [Releases](https://github.com/nissy/kipple/releases).
2. Move `Kipple.app` to the Applications folder.
3. Launch Kipple from Applications or Spotlight.
4. Configure hotkeys and settings as needed.

## Requirements

- macOS 14.0 or later

## License

MIT License

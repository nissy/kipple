# Kipple


[Japanese README](README.ja.md)

![Kipple icon](https://github.com/user-attachments/assets/2c295e8a-2fcd-4102-8e46-75bcbaaa79d9)

Kipple is a local-first clipboard manager for macOS.

It keeps your copied text searchable, editable, organized, and ready to paste again. It is built for people who copy lots of text while writing, researching, coding, filling forms, or moving information between apps.

[Download the latest release](https://github.com/nissy/kipple/releases/latest/download/Kipple.dmg)

<img width="735" height="881" src="https://github.com/user-attachments/assets/ff419919-fdb5-49ce-b7e5-1648e230b0e0" />

## Why Kipple?

Kipple is more than a clipboard history list.

- Search copied text and bring it back instantly
- Keep important clips in custom categories
- Pin clips to the desktop as notes
- Compare clipboard text with a selection in another app
- Edit clipboard text in the Live Editor before saving or pasting
- Format JSON and YAML directly from the editor
- Paste multiple clips in order with Queue
- Capture text from the screen with OCR
- Keep clipboard history on your Mac

## Features

### Clipboard History

Kipple automatically saves copied text and shows it in a compact menu bar window. Selecting an item copies it back to the clipboard.

Each history item can hold up to 80,000 characters. Use **Add History Item** to create an entry manually, or right-click an entry and choose **Edit Item** to update its title, text, and categories.

History items can include the following information.

- copied text
- title
- copied time
- source app
- source window title
- source web link, when available
- URL classification
- user category

Duplicate copies are moved to the top instead of creating another identical item.

### Search and Categories

Search by text, title, or source app. Select multiple category filters and choose whether clips must match all or any of them. Clips in custom categories stay available when history is trimmed or cleared.

Kipple includes built-in `None`, `URL`, `OCR`, and `AI` categories. You can also add your own categories with names and SF Symbol icons. See the [MCP setup guide (Japanese)](MCP.md) for adding clips from an AI client.

### Desktop Notes

Click the pin icon next to a history item to post it to your desktop. Edit or copy the note, switch between Markdown and plain text, and choose from 16 colors. Use **Fit to Content** to resize the note to its text. The note also shows the source app, window title, and a clickable web link when available.

Use **Show Only Desktop Notes** to find posted items in history. Kipple restores open notes with their position, size, and color when you reopen the app. Posted items stay available when history is trimmed or cleared.

In **Settings → Desktop Notes**, choose the default display format and the monitor where new notes appear. With **Create a note on repeated copy** enabled, copy the same text three times in a row within five seconds in another app to post a note.

### Compare Text

Set a shortcut in **Settings → General → Compare Text**. Copy the first text, select the second text in the active app, and press your shortcut. The clipboard appears on the left and the selection appears on the right. Each side supports up to 80,000 characters.

Line numbers and character-level highlights show what changed. When there are multiple differences, use **Previous Difference** and **Next Difference** to jump between them. Click **Copy** in the **Selected Text** header to copy the selection and close the window. Press `Esc` or click outside to dismiss it.

Kipple keeps the temporary comparison copy out of history and restores the original clipboard. A new copy made during the comparison takes precedence and cancels the comparison.

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

Turn on Queue, select clips from history, then press `Command + V` repeatedly. Kipple advances to the next queued item after each paste. Turn on **Repeat** to loop through the queue.

In normal mode, either hold a history item for half a second or drag and drop it inside the history list to start Queue with that item. Dragging does not require a long press. In Queue mode, drag without waiting: dropping an unqueued item adds it at the insertion line; dragging a queued item changes its position. The area below the last queue entry, including the space below the history rows, appends to the queue. This also works while searching, filtering by category, or scrolling past the queue entries. When the queue is empty or no queue entries are displayed, dropping inside the list appends the item. During a drag, pressing `Esc` or dropping outside the list cancels without changing the mode or queue. Starting Queue with a long press or adding or reordering by dragging does not change the clipboard contents. A short click still copies in normal mode or adds/removes an item in Queue mode.

Use the plain text paste shortcut (default: `Command + Shift + V`) to paste a queued item without formatting. Each shortcut prepares its item before sending the paste command. Kipple leaves that item on the clipboard until the next operation, including after the queue finishes, so delayed paste requests can still read it. Review the required paste permission in **Settings → Permission**.

Change or clear the plain text paste shortcut in **Settings → General → Pasting**. Editing and using this shortcut requires the same permission. The settings show a link when access is missing. Revoking access stops the shortcut and keeps your chosen keys for when access is granted again.

Turn on **Swap paste formatting** in the same settings to make `Command + V` paste plain text and the other shortcut (default: `Command + Shift + V`) paste with formatting. This applies to normal and Queue modes. `Command + V` continues to paste images and files unchanged. Clearing the other shortcut also turns off swapping.

In normal mode, Kipple temporarily retains the original clipboard, including formatting and app-specific data. After a plain text paste, use the formatting shortcut to paste the same copy with its original formatting. A new copy discards the retained data. This requires Kipple to be running and does not use timed restoration or the destination app’s plain text command. Pasting through a menu or mouse action uses the clipboard’s current format.

Queue is useful for forms, repetitive data entry, and moving several values between apps without copying each item manually.

### Screen Text Capture

Screen Text Capture lets you select an area of the screen and extract text with macOS Vision OCR.

Recognized text is copied to the clipboard and saved to history. OCR processing happens on your Mac.
Paragraph breaks are preserved, and recognized tables are copied as tab-separated text for spreadsheets.

### Paste on Selection

Paste on Selection can paste a selected history item directly into the previously active app. This is useful when you want one-click selection and paste behavior.

## Permissions on macOS 26 or later

Open **Kipple Settings → Permission** to check access and open the matching page in **System Settings → Privacy & Security**.

| Permission | Used for |
| --- | --- |
| Screen & System Audio Recording | Screen Text Capture (OCR) and retrieving source window names. Kipple captures still images; it does not record audio. |
| Accessibility (macOS 26) / Device Control and Data Access (macOS 27 or later) | Reading the selection for Compare Text and sending paste commands for Queue, Paste on Selection, and plain text paste. |

Enable **Kipple** on the corresponding page. Return to Kipple to check the permission status. If macOS requests a restart or the status remains Not Granted, quit and reopen Kipple. If it is still Not Granted, remove the old Kipple entry from that permission list, add the Kipple.app you are currently using, and enable it again. This may be necessary after changing the app's signing identity or switching between installed and development copies.

Clipboard history, search, and copying history items do not require these permissions. Input Monitoring and Automation permissions are not required. MCP communicates through a local Unix socket and does not require Local Network permission.

Clipboard reading is controlled separately by macOS. **Settings → Permission → Clipboard Access** shows the current policy and lets you retry a failed read. If macOS asks, allow access; if blocked, review Kipple under Privacy & Security. Changing the policy to allow reading resumes capture without requiring another copy. Kipple does not repeatedly retry the same denied read.

Launch at login reflects the actual macOS registration state. If approval is pending, use the displayed link to Login Items; turning the toggle off also removes a pending registration.

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

- Mac with Apple silicon (M1 or later)
- macOS 26.0 (Tahoe) or later

## Development

`make run` builds and launches the development app, signing it with a **Developer ID Application** certificate. Install Xcode 27 or later (macOS 27 SDK), XcodeGen, and the signing certificate with its private key first. To use another certificate, specify `make run DEV_CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=YOUR_TEAM_ID`.

Keep the signing identity consistent between builds. Unsigned or ad-hoc builds can appear as Not Granted even when Kipple is enabled in System Settings. Changing the signing identity may require granting permissions again and restarting Kipple.

## License

MIT License

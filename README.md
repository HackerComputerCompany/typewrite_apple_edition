# Typewrite for iPad

A distraction-free, typewriter-style writing environment for iPad, ported from the [typewrite_os](https://github.com/HackerComputerCompany/typewrite_os) X11 application.

Like the original, this is a **game-style** app — no UITextView, no platform text widgets. Text is rendered character-by-character into a fixed-width grid using Core Graphics and Core Text, with hardware keyboard input via `pressesBegan` and software keyboard via `UIKeyInput`. The same fonts, sounds, and character grid model are preserved from the X11 version.

## How It Works

- **CanvasView** is a custom `UIView` that draws characters into a grid each frame using `draw(_ rect:)`. It maintains a `TwDoc` character grid (multi-page fixed-width array) and renders it like a game framebuffer.
- **Sound effects** are per-font WAV files. Delete/backspace plays the key sound **in reverse** (PCM data flipped) for a distinct delete feel.
- **Autosave** writes the document text on every keystroke (1s debounce) and immediately on background, using `ReferenceFileDocument`.
- **Settings** persist via `UserDefaults` and sync to `CanvasView` on every SwiftUI state change.
- **Typewriter view** anchors the cursor to the bottom row, scrolling content upward — exactly like a real typewriter.

## Architecture

| File | Purpose |
|---|---|
| `CanvasView.swift` | Custom UIView renderer, keyboard input, cursor, draw loop |
| `DocumentModel.swift` | `TwCore` + `TwDoc` character grid model |
| `FontRegistry.swift` | Font loading, CTFontManager registration, cell metrics |
| `SoundManager.swift` | Key/carriage/bell WAV playback per font; reversed for delete |
| `PaperTheme.swift` | 10 background/ink colour schemes |
| `EditorView.swift` | Main SwiftUI view: toolbar, autosave, toast, help, file I/O |
| `SettingsStore.swift` | UserDefaults-backed settings |
| `PlainTextDocument.swift` | ReferenceFileDocument for .txt autosave |
| `HelpOverlay.swift` | Keyboard shortcuts overlay |
| `HelloiPadApp.swift` | App entry point (DocumentGroup) |

## Fonts

8 bundled TTF fonts (in `Fonts/`) + system mono fallback:

- **Virgil** (hand-drawn) → virgil_pencil sound
- **Inter** (sans UI) → ui_tap sound
- **Special Elite** (distressed typewriter) → typewriter_key/carriage/bell
- **Courier Prime** (screenplay typewriter) → typewriter_key/carriage/bell
- **VT323** (retro terminal) → terminal_blip
- **Press Start 2P** (8-bit pixel) → terminal_blip
- **IBM Plex Mono** (corporate mono) → ibm_keyboard
- **Share Tech Mono** (retro sci-fi) → arcade_blip
- **System Mono** → simple_blip

## Keyboard

Hardware keyboard required for best experience. The iOS system keyboard also works via `UIKeyInput` conformance — it appears automatically when no hardware keyboard is attached and hides when one is connected.

| Key | Action |
|---|---|
| Printable ASCII | Type character |
| Enter / Return | New line (carriage sound on typewriter fonts) |
| Backspace | Delete backward (reversed key sound) |
| Delete | Delete forward (reversed key sound) |
| Arrow keys | Move cursor |
| Home / End | Line start / end |
| Page Up / Down | Previous / next page |
| Insert | Toggle insert/typeover mode |
| Toolbar buttons | Font, theme, cursor, margins, typewriter, line numbers |

## Building

Open `HelloiPad.xcodeproj` in Xcode 16+, select iPad simulator or device, build & run.

Requires iPadOS 17.0+ and an external hardware keyboard for the full experience. The software keyboard also works for basic text entry.
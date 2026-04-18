# Typewrite for iPad

A distraction-free, typewriter-style writing environment for iPad, ported from the [typewrite_os](https://github.com/HackerComputerCompany/typewrite_os) X11 application.

Like the original, this is a **game-style** app — no UITextView, no platform text widgets. Text is rendered character-by-character into a custom `UIView` using Core Graphics and Core Text, with direct hardware keyboard input via `pressesBegan`. The same fonts, sounds, and "translate" logic (character grid model, bell at margin, typewriter bottom-anchored view) are preserved from the X11 version.

## Architecture

| File | Purpose |
|---|---|
| `CanvasView.swift` | Custom UIView: pixel-buffer rendering, hardware keyboard input, cursor, typewriter rule |
| `CanvasRepresentable.swift` | SwiftUI ↔ UIView bridge |
| `DocumentModel.swift` | `TwCore` + `TwDoc` — multi-page character grid model ported from `tw_core.c`/`tw_doc.c` |
| `FontRegistry.swift` | Loads 8 bundled TTF fonts + system mono, registers with Core Text, computes cell metrics |
| `SoundManager.swift` | Key/carriage/bell sounds per font, using AVAudioPlayer |
| `PaperTheme.swift` | 10 background+ink colour schemes from the X11 app |
| `SettingsStore.swift` | UserDefaults persistence for font, theme, cursor, margins, etc. |
| `EditorView.swift` | Main SwiftUI view: toolbar, toast overlay, help, document picker |
| `HelpOverlay.swift` | Keyboard shortcuts overlay |
| `PlainTextDocument.swift` | SwiftUI `FileDocument` for .txt import/export |
| `HelloiPadApp.swift` | App entry point |

## Fonts

All 8 fonts from the original project are bundled as TTF files under `Fonts/`:

- Virgil (hand-drawn)
- Inter (sans UI)
- **Special Elite** (distressed typewriter)
- **Courier Prime** (screenplay/typewriter)
- **VT323** (retro terminal)
- **Press Start 2P** (8-bit pixel)
- **IBM Plex Mono** (corporate mono)
- **Share Tech Mono** (retro sci-fi)
- System Mono (built-in fallback)

Font-sound mapping mirrors the X11 app: typewriter fonts get key+carriage+bell sounds, terminal fonts get blip sounds, etc.

## Sounds

All 18 WAV sound effects from the original repo are bundled under `Sounds/`.

## Keyboard Shortcuts

Hardware keyboard required. Key mappings:

| Key | Action |
|---|---|
| Printable ASCII | Type character |
| Enter | New line (carriage sound on typewriter fonts) |
| Backspace | Delete backward |
| Delete | Delete forward |
| Arrow keys | Move cursor |
| Home / End | Line start / end |
| Page Up / Down | Previous / next page |
| Insert | Toggle insert/typeover mode |
| Toolbar buttons | Font, theme, cursor, margins, typewriter view, line numbers |

## Building

Open `HelloiPad.xcodeproj` in Xcode 16+, select iPad simulator, build & run.

Requires iPadOS 17.0+ and an external hardware keyboard for the full experience.
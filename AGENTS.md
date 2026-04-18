# AGENTS.md — Typewrite for iPad

## Purpose

iPad port of [typewrite_os](https://github.com/HackerComputerCompany/typewrite_os) (specifically the X11 app). A distraction-free, typewriter-style writing environment. Game-style rendering: no UITextView — custom UIView blits characters into a grid, hardware keyboard only.

## Key Files

| Path | What |
|---|---|
| `HelloiPad/CanvasView.swift` | Core renderer + keyboard input handler + cursor blink + draw loop |
| `HelloiPad/DocumentModel.swift` | `TwCore` + `TwDoc` character grid model (port of tw_core.c/tw_doc.c) |
| `HelloiPad/FontRegistry.swift` | Font loading, registration, cell metrics computation |
| `HelloiPad/SoundManager.swift` | Key/carriage/bell WAV playback per font; reversed playback for delete |
| `HelloiPad/PaperTheme.swift` | 10 background/ink colour schemes |
| `HelloiPad/EditorView.swift` | Main SwiftUI shell: toolbar, autosave, toast, help, file I/O |
| `HelloiPad/SettingsStore.swift` | UserDefaults-backed settings (font, theme, cursor, margins, etc.) |
| `HelloiPad/PlainTextDocument.swift` | ReferenceFileDocument for .txt — autosave via debounce + background |
| `HelloiPad/HelpOverlay.swift` | Keyboard shortcuts overlay |
| `HelloiPad/HelloiPadApp.swift` | App entry point (DocumentGroup + ReferenceFileDocument) |

## Build

```
xcodebuild -project HelloiPad.xcodeproj -scheme HelloiPad -destination 'platform=iOS Simulator,name=iPad (A16)' build
```

Or open in Xcode 16+ and Cmd+R.

## Architecture

```
HelloiPadApp (DocumentGroup)
  └─ EditorView (SwiftUI)
       ├─ CanvasRepresentable (UIViewRepresentable bridge)
       │    └─ CanvasView (UIView — game-style renderer)
       │         ├─ TwDoc / TwCore (character grid model)
       │         ├─ FontRegistry (8 TTF + system mono)
       │         ├─ SoundManager (WAV playback, reversed for delete)
       │         ├─ SettingsStore (UserDefaults)
       │         └─ PaperTheme (10 colour schemes)
       ├─ HelpOverlay (SwiftUI)
       └─ Toolbar (SwiftUI, hideable, combined bottom bar)
```

## X11 → iOS Translation Map

| X11 Concept | iOS Equivalent |
|---|---|
| `XPutImage` pixel buffer | `UIView.draw()` with Core Graphics |
| `XLookupKeysym` key events | `pressesBegan(_:with:)` + `UIKeyInput` on `CanvasView` |
| `tw_bitmapfont_uefi.c` glyph blit | Core Text via `NSAttributedString.draw()` |
| `tw_core.c` / `tw_doc.c` | `TwCore` + `TwDoc` in `DocumentModel.swift` |
| `tw_sound.c` (SDL2) | `SoundManager` (AVAudioPlayer, NSCache pool) |
| `tw_x11_settings.c` (JSON file) | `SettingsStore` (UserDefaults) |
| `mono_ms()` timer for cursor blink | `CADisplayLink` via `DisplayLinkProxy` |
| `typewriter_buf_row_for_sy()` | `typewriterBufferRow(for:)` in `CanvasView` |
| Page margins (F6) | `pageMargins` in `SettingsStore` |
| Typewriter view (F8) | `typewriterView` in `SettingsStore` |
| Background cycle (F4) | `PaperTheme` enum (10 colours) |
| Autosave via file monitoring | `ReferenceFileDocument` + 1s debounce + background save |

## Conventions

- No UITextView, no UITextViewDelegate — all rendering is game-style
- Hardware keyboard input via `pressesBegan`; software keyboard via `UIKeyInput`
- Sound effects are WAV files bundled in `Sounds/` directory
- Fonts are TTF files bundled in `Fonts/` directory, registered at runtime with Core Text
- Delete sounds are the key sounds played in reverse (PCM data reversed in WAV chunk)
- Autosave: `EditorView.saveNow()` writes `canvas.doc.fullText()` to `document.text`, debounced 1s after keystroke, immediate on background
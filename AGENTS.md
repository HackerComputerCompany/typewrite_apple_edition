# AGENTS.md — Typewrite for iPad

## Purpose

iPad port of [typewrite_os](https://github.com/HackerComputerCompany/typewrite_os) (specifically the X11 app). A distraction-free, typewriter-style writing environment. Game-style rendering: no UITextView — custom UIView blits characters into a grid, hardware keyboard only.

## Key Files

| Path | What |
|---|---|
| `HelloiPad/CanvasView.swift` | Core renderer + keyboard input handler |
| `HelloiPad/DocumentModel.swift` | `TwCore` + `TwDoc` character grid model |
| `HelloiPad/FontRegistry.swift` | Font loading, registration, cell metrics |
| `HelloiPad/SoundManager.swift` | Key/carriage/bell WAV playback per font |
| `HelloiPad/PaperTheme.swift` | 10 background/ink colour schemes |
| `HelloiPad/EditorView.swift` | Main SwiftUI shell (toolbar, toast, help) |
| `HelloiPad/SettingsStore.swift` | UserDefaults-backed settings |

## Build

```
xcodebuild -project HelloiPad.xcodeproj -scheme HelloiPad -destination 'platform=iOS Simulator,name=iPad (A16)' build
```

Or open in Xcode 16+ and Cmd+R.

## X11 → iOS Translation Map

| X11 Concept | iOS Equivalent |
|---|---|
| `XPutImage` pixel buffer | `UIView.draw()` with Core Graphics |
| `XLookupKeysym` key events | `pressesBegan(_:with:)` on `CanvasView` |
| `tw_bitmapfont_uefi.c` glyph blit | Core Text `CTFontDrawGlyphs` / NSAttributedString |
| `tw_core.c` / `tw_doc.c` | `TwCore` + `TwDoc` in `DocumentModel.swift` |
| `tw_sound.c` (SDL2) | `SoundManager` (AVAudioPlayer) |
| `tw_x11_settings.c` (JSON file) | `SettingsStore` (UserDefaults) |
| `mono_ms()` timer for cursor blink | `CADisplayLink` in `CanvasView` |
| `typewriter_buf_row_for_sy()` | `typewriterBufferRow(for:)` in `CanvasView` |
| Page margins (F6) | `pageMargins` in `SettingsStore` |
| Typewriter view (F8) | `typewriterView` in `SettingsStore` |
| Background cycle (F4) | `PaperTheme` enum (10 colours) |

## Conventions

- No UITextView, no UITextViewDelegate — all rendering is game-style
- Hardware keyboard required; no on-screen keyboard
- Sound effects are WAV files bundled in `Sounds/` directory
- Fonts are TTF files bundled in `Fonts/` directory, registered at runtime with Core Text
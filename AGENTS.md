# AGENTS.md — Typewrite Apple Edition

## Purpose

Native **iPad + macOS** port of [typewrite_os](https://github.com/HackerComputerCompany/typewrite_os) (X11 app). Distraction-free, typewriter-style writing. Game-style rendering on iPad: no `UITextView` — custom `UIView` draws a character grid; macOS uses `CanvasNSView` (`NSView`) with the same model and shared Swift sources.

## Key Files

| Path | What |
|---|---|
| `typewrite_apple_edition/CanvasView.swift` | Core iOS renderer + keyboard + cursor blink + draw loop |
| `typewrite_apple_edition_macOS/CanvasNSView.swift` | AppKit renderer + keyboard (shared model with iPad) |
| `typewrite_apple_edition/DocumentModel.swift` | `TwCore` + `TwDoc` character grid model (port of tw_core.c/tw_doc.c) |
| `typewrite_apple_edition/FontRegistry.swift` | Font loading, registration, cell metrics computation |
| `typewrite_apple_edition/SoundManager.swift` | Key/carriage/bell WAV per font; delete = random key WAV reversed, same pick until 10s after last delete |
| `typewrite_apple_edition/PaperTheme.swift` | 10 background/ink colour schemes |
| `typewrite_apple_edition/EditorView.swift` | Main SwiftUI shell: toolbar, autosave, toast, help, file I/O |
| `typewrite_apple_edition/SettingsStore.swift` | UserDefaults-backed settings (font, theme, cursor, margins, etc.) |
| `typewrite_apple_edition/PlainTextDocument.swift` | ReferenceFileDocument for .txt — autosave via debounce + background |
| `typewrite_apple_edition/HelpOverlay.swift` | Keyboard shortcuts overlay |
| `typewrite_apple_edition/TypewriteAppleEditionApp.swift` | iOS `@main` entry (DocumentGroup + ReferenceFileDocument) |
| `typewrite_apple_edition_macOS/TypewriteAppleEditionMacApp.swift` | macOS `@main` entry |

## Build

The repository root folder is **`typewrite_apple_edition`**. Open `Typewrite.xcodeproj` in Xcode from this directory.

iPad (example simulator):

```
xcodebuild -project Typewrite.xcodeproj -scheme Typewrite -destination 'platform=iOS Simulator,name=iPad (A16)' build
```

macOS:

```
xcodebuild -project Typewrite.xcodeproj -scheme Typewrite_macOS -destination 'platform=macOS' build
```

Or open `Typewrite.xcodeproj` in Xcode 16+ and Cmd+R.

**Changelog and bug write-ups:** [CHANGELOG.md](CHANGELOG.md) (release notes) and [docs/bug-reports/README.md](docs/bug-reports/README.md) (BR-00x technical reports, linked from the changelog).

**Window chrome (macOS only):** **View → Window Background…** (⌥⌘B) or the dashed-rectangle toolbar control opens a sheet. **Background blur** (0–100) turns on `NSVisualEffectView` behind the editor (0 = solid); **Surround transparency** (1–100%) fades the dark surround tint so the desktop shows through. Values persist in `SettingsStore` (`macChromeBlurPercent`, `macChromeTransparencyPercent`). `CanvasNSView` uses the same tint alpha for margin fills.

**Signing:** Bundle IDs were renamed to `com.hackercomputercompany.typewrite.apple.edition` (iOS) and `…typewrite.apple.edition.macOS` (Mac). After pulling this change, open the project in Xcode, select each target, and confirm **Signing & Capabilities** resolves automatic signing (Xcode may prompt to register the new identifiers with your team).

## Architecture

```
TypewriteAppleEditionApp / TypewriteAppleEditionMacApp (DocumentGroup)
  └─ EditorView (SwiftUI)
       ├─ CanvasRepresentable
       │    └─ CanvasView (iOS) or CanvasNSView (macOS)
       │         ├─ TwDoc / TwCore (character grid model)
       │         ├─ FontRegistry (8 TTF + system mono)
       │         ├─ SoundManager (WAV playback; delete = random reversed key, 10s idle session)
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
| `mono_ms()` timer for cursor blink | `CADisplayLink` (iOS); `Timer` on main run loop (macOS `CanvasNSView`) |
| `typewriter_buf_row_for_sy()` | `typewriterBufferRow(for:cursorY:viewRows:)` in `CanvasView` / `CanvasNSView` |
| `compute_view_layout()` (Letter margins, full width) | `recalcLayout()` in `CanvasView` / `CanvasNSView` |
| Page margins (F6) | `pageMargins` in `SettingsStore` |
| Typewriter view (F8) | `typewriterView` in `SettingsStore` |
| Background cycle (F4) | `PaperTheme` enum (10 colours) |
| Autosave via file monitoring | `ReferenceFileDocument` + 1s debounce + background save |

## Conventions

- No UITextView, no UITextViewDelegate — iOS rendering is game-style
- Hardware keyboard input via `pressesBegan`; software keyboard via `UIKeyInput`
- Sound effects are WAV files bundled in `Sounds/` directory
- Fonts are TTF files bundled in `Fonts/` directory, registered at runtime with Core Text
- Delete/backspace: random key-like WAV (excluding carriage/bell), reversed; new random after 10s without a delete
- Autosave: `EditorView.saveNow()` writes `canvas.doc.fullText()` to `document.text`, debounced 1s after keystroke, immediate on background

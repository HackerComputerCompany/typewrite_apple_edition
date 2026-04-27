# Typewrite Apple Edition

A distraction-free, typewriter-style writing environment for **iPad and macOS**, ported from the [typewrite_os](https://github.com/HackerComputerCompany/typewrite_os) X11 application.

Like the original, this is a **game-style** app — no UITextView, no platform text widgets. Text is rendered character-by-character into a fixed-width grid using Core Graphics and Core Text, with hardware keyboard input via `pressesBegan` and software keyboard via `UIKeyInput`. The same fonts, sounds, and character grid model are preserved from the X11 version.

## How It Works

- **CanvasView** is a custom `UIView` that draws characters into a grid each frame using `draw(_ rect:)`. It maintains a `TwDoc` character grid (multi-page fixed-width array) and renders it like a game framebuffer.
- **Sound effects** are per-font WAV files for typing. Delete/backspace picks a **random** key-like sample, plays it **in reverse** (PCM flipped), and **reuses** that sample until **10 seconds** after the last delete so a burst of backspace does not constantly change timbre.
- **Autosave** writes the document text on every keystroke (1s debounce) and immediately on background, using `ReferenceFileDocument`.
- **Settings** persist via `UserDefaults` and sync to `CanvasView` on every SwiftUI state change.
- **Typewriter view** anchors the cursor to the bottom row, scrolling content upward — exactly like a real typewriter.

## Architecture

| File | Purpose |
|---|---|
| `CanvasView.swift` | Custom UIView renderer, keyboard input, cursor, draw loop |
| `DocumentModel.swift` | `TwCore` + `TwDoc` character grid model |
| `FontRegistry.swift` | Font loading, CTFontManager registration, cell metrics |
| `SoundManager.swift` | Key/carriage/bell per font; delete = random reversed key sample (10s idle before new random) |
| `PaperTheme.swift` | 10 background/ink colour schemes |
| `EditorView.swift` | Main SwiftUI view: toolbar, autosave, toast, help, file I/O |
| `SettingsStore.swift` | UserDefaults-backed settings |
| `PlainTextDocument.swift` | ReferenceFileDocument for .txt autosave |
| `HelpOverlay.swift` | Keyboard shortcuts overlay |
| `TypewriteAppleEditionApp.swift` | iOS app entry (DocumentGroup) |
| `typewrite_apple_edition_macOS/TypewriteAppleEditionMacApp.swift` | macOS app entry (DocumentGroup) |

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
| Backspace | Delete backward (random reversed key sound; same sample until 10s idle) |
| Delete | Delete forward (same delete sound behaviour as backspace) |
| Arrow keys | Move cursor |
| Home / End | Line start / end |
| Page Up / Down | Previous / next page |
| Insert | Toggle insert/typeover mode |
| Toolbar buttons | Font, theme, cursor, margins, typewriter, line numbers |

## Building

From the **`typewrite_apple_edition`** repository directory, open `Typewrite.xcodeproj` in Xcode 16+. Use the **Typewrite** scheme for iPad (simulator or device) or **Typewrite_macOS** for Mac, then build and run.

Requires iPadOS 17.0+ (iPad target) or macOS 14.0+ (Mac target). A hardware keyboard is recommended on iPad; the software keyboard also works for basic text entry.

**Changelog:** [CHANGELOG.md](CHANGELOG.md). **Bug report write-ups** (repro, root cause, fix): [docs/bug-reports/README.md](docs/bug-reports/README.md).

On **macOS**, use **View → Window Background…** (⌥⌘B) to adjust frosted **blur** (0–100) and **surround transparency** (1–100%, how much the dark border fades to show the desktop through).

Because the bundle identifiers changed, open **Signing & Capabilities** in Xcode once per target so automatic signing can register the new IDs with your Apple Developer team.
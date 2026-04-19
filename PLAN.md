# PLAN — Typewrite Apple Edition (iPad + macOS)

## Phase 1: Foundation (Complete)
- [x] Game-style custom UIView renderer (`CanvasView`) — no UITextView
- [x] Hardware keyboard input via `pressesBegan` + `UIKeyInput` for software KB
- [x] Character grid document model (`TwDoc`/`TwCore`) ported from tw_core/tw_doc
- [x] Core Text font registration and glyph metrics (`FontRegistry`)
- [x] 10 colour themes from X11 app (`PaperTheme`)
- [x] 5 cursor modes (bar, blink-bar, block, blink-block, hidden)
- [x] Typewriter bottom-anchored view (F8 equivalent)
- [x] Page margins mode (F6 equivalent)
- [x] Sound effects per-font keyclick, carriage, bell (`SoundManager`)
- [x] Delete sounds: random key sample from pool, reversed (PCM); new pick after 10s idle (`SoundManager`)
- [x] Settings persistence (`SettingsStore` / UserDefaults)
- [x] Help overlay with keyboard shortcuts
- [x] .txt file open/export via `ReferenceFileDocument`
- [x] Autosave: 1s debounce on keystroke + immediate on background
- [x] System keyboard (no custom soft keyboard)
- [x] Combined hideable toolbar (font, theme, cursor, margins, insert, file, help)
- [x] `DisplayLinkProxy` to break CADisplayLink retain cycle

## Phase 2: Polish & Features
- [ ] Typing pace tracking (WPM, session word count) — status toast
- [ ] PDF export (render grid pages to CGContext, write PDF)
- [ ] Cursor cross-page navigation with smooth scroll
- [x] Line number gutter modes (ascending/descending) — toolbar / settings cycle + render
- [x] Columns-per-line cycling (50→65 in margins mode) — toolbar + `SettingsStore`
- [x] Word wrap soft-wrap logic in `TwDoc` (`wordWrap`, `trySoftWrap`)
- [ ] Insert mode line-join on backspace at col 0
- [x] Resize reflow — `layoutSubviews` / `setFrameSize` → `recalcLayout()` + `doc.resize` when grid changes
- [ ] On-screen minimal toolbar for users without hardware keyboard

## Phase 3: Polish
- [ ] Haptic feedback on key press
- [ ] App icon and launch screen
- [ ] Test on real iPad with hardware keyboard
- [ ] Performance profiling for large documents (100+ pages)
- [ ] Accessibility: VoiceOver support for cursor position

## Source Mapping

| X11 File | iOS File | Notes |
|---|---|---|
| `tw_core.c` | `DocumentModel.swift` TwCore | Direct port |
| `tw_doc.c` | `DocumentModel.swift` TwDoc | Direct port, insert/soft-wrap not yet |
| `tw_bitmapfont_uefi.c` | `FontRegistry.swift` | Replaced bitmap blit with Core Text |
| `tw_sound.c` | `SoundManager.swift` | SDL2 → AVAudioPlayer, NSCache pool; delete = random key WAV reversed, 10s idle session |
| `tw_x11_settings.c` | `SettingsStore.swift` | JSON file → UserDefaults |
| `main_x11.c` render() | `CanvasView.swift` / `CanvasNSView.swift` draw() | XPutImage → Core Graphics |
| `main_x11.c` key handler | `CanvasView.swift` pressesBegan | XLookupKeysym → UIKey.keyCode + UIKeyInput |
| `main_x11.c` ToastState | `EditorView.swift` toastOverlay | Status bar toast |
| — | `PlainTextDocument.swift` | ReferenceFileDocument for autosave |
# PLAN — Typewrite for iPad

## Phase 1: Foundation (Complete)
- [x] Game-style custom UIView renderer (`CanvasView`) — no UITextView
- [x] Hardware keyboard input via `pressesBegan`
- [x] Character grid document model (`TwDoc`/`TwCore`) ported from `tw_core.c`/`tw_doc.c`
- [x] Core Text font registration and glyph metrics (`FontRegistry`)
- [x] 10 colour themes from X11 app (`PaperTheme`)
- [x] 5 cursor modes (bar, blink-bar, block, blink-block, hidden)
- [x] Typewriter bottom-anchored view (F8 equivalent)
- [x] Page margins mode (F6 equivalent)
- [x] Sound effects per-font keyclick, carriage, bell (`SoundManager`)
- [x] Settings persistence (`SettingsStore` / UserDefaults)
- [x] Help overlay
- [x] .txt file open/export via `PlainTextDocument`

## Phase 2: Polish & Features
- [ ] Typing pace tracking (WPM, session word count) — status toast
- [ ] Autosave (10-second idle timer)
- [ ] PDF export (render grid pages to CGContext, write PDF)
- [ ] Cursor cross-page navigation with smooth scroll
- [ ] Line number gutter modes (ascending/descending)
- [ ] Columns-per-line cycling (50→65 in margins mode)
- [ ] Word wrap soft-wrap logic in `TwDoc`
- [ ] Insert mode line-join on backspace at col 0
- [ ] Resize reflow (recalculate grid on rotation)

## Phase 3: Polish
- [ ] Haptic feedback on key press
- [ ] On-screen minimal keyboard toolbar for common actions (iPad without hardware keyboard)
- [ ] Dark mode / dynamic type awareness
- [ ] App icon and launch screen
- [ ] Test on real iPad with hardware keyboard
- [ ] Performance profiling for large documents (100+ pages)

## Source Mapping

| X11 File | iOS File | Notes |
|---|---|---|
| `tw_core.c` | `DocumentModel.swift` TwCore | Direct port |
| `tw_doc.c` | `DocumentModel.swift` TwDoc | Direct port, insert/soft-wrap not yet |
| `tw_bitmapfont_uefi.c` | `FontRegistry.swift` | Replaced bitmap blit with Core Text |
| `tw_sound.c` | `SoundManager.swift` | SDL2 → AVAudioPlayer |
| `tw_x11_settings.c` | `SettingsStore.swift` | JSON file → UserDefaults |
| `main_x11.c` render() | `CanvasView.swift` draw() | XPutImage → Core Graphics |
| `main_x11.c` key handler | `CanvasView.swift` pressesBegan | XLookupKeysym → UIKey.keyCode |
| `main_x11.c` ToastState | `EditorView.swift` toastOverlay | Status bar toast |
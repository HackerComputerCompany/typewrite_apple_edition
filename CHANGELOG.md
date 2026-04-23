# Changelog

All notable changes to **Typewrite Apple Edition** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **macOS:** **View → Window Background…** (⌥⌘B) and toolbar control to adjust frosted window **blur** (0–100) and **surround transparency** (1–100%). Persists in `SettingsStore` (`macChromeBlurPercent`, `macChromeTransparencyPercent`).

### Fixed

- **Document load / import:** Opening a file or applying `PlainTextDocument` text on launch could leave the canvas **stale** until a keypress, because `TwDoc.load` does not go through the normal input path that calls `setNeedsDisplay`. The editor now **refreshes the canvas** immediately and on the next main-runloop pass after load. ([BR-001](docs/bug-reports/BR-001-canvas-not-redrawn-after-document-load.md))
- **Typewriter view after import:** Forcing the cursor to page 0 / `(0,0)` after `load` made **multi-line** files look almost **blank** in typewriter mode (only one screen row shows buffer content when `cy == 0`). The loader now **leaves the cursor at the end of the parsed text** so the typewriter viewport shows the right window of lines. ([BR-002](docs/bug-reports/BR-002-typewriter-view-blank-after-import.md))
- **Text import:** Line endings: split on the platform **newline** set while **excluding** form feed (U+000C) so page breaks from `fullText` still map to `newPage()`. **Unicode** spaces and non-ASCII newlines in paste/keyboard paths map through `putc` with a normalized **space** for the cell. ([BR-003](docs/bug-reports/BR-003-text-import-unicode-line-endings-and-spaces.md))
- **Build:** `textLoadLineBreakSet` now uses a **mutable** `NSCharacterSet.newlines` copy and bridges to `CharacterSet` correctly (avoids wrong overload / compile errors).

### Changed

- **Behaviour vs X11 `twdoc_load`:** The C reference always resets the cursor to the top of page 0 after load. On Apple, after load the cursor remains at the **end of file** to match typewriter rendering and a typical “continue writing” flow.

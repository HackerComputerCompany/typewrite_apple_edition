# BR-002 — Typewriter view looks empty after file import (cursor at row 0)

**Status:** Fixed  
**Date reported:** 2026-04-19  
**Area:** `DocumentModel.TwDoc.load`, `CanvasView` / `CanvasNSView` typewriter mapping

## Summary

With **Typewriter** mode on, after importing or opening a **multi-line** file, the paper appeared **mostly blank** (user described needing to use arrow keys to “get it to render”). The grid actually contained the text, but the **typewriter screen-row mapping** hid almost all of it when the cursor was stuck at **buffer row 0**.

## Environment

- `settings.typewriterView == true` (default in many sessions)
- `DocumentModel.load` previously ended by resetting `curPage` and cursor to **(0,0)** on page 0, matching X11 `twdoc_load`.

## Steps to reproduce (before fix)

1. Turn on typewriter view.
2. Import a file with many lines (e.g. 20+).
3. Observe: only a **thin** slice of the document appears (often a single line at the bottom of the paper), the rest looks like margin / blank.

## Expected vs actual

- **Expected:** A readable window of the loaded text (at minimum, the region around the “current” position).  
- **Actual:** `typewriterBufferRow` with `cursorY == 0` maps almost all **screen** rows to **buffer row -1** (blank strip); only the **last** screen row shows `bufferRow == 0`, so the document looked empty.

## Root cause

- **Typewriter mapping** (port of X11 `typewriter_buf_row_for_sy`) is **cursor-centric**; when the cursor sits on the first buffer row, most screen rows are intentionally “above the growing document” and draw blank.
- Resetting the cursor to `(0,0)` after every load maxed that effect for any file that fills row 0 and beyond.

## Fix

- Stop forcing `curPage = 0; cx, cy = 0` at the end of `load`. Leave the cursor where parsing leaves it, typically the **end of the loaded text**, so `cy` (and `curPage` for multi-page) positions the viewport in a useful range.  
- This **differs** from X11’s always-top-left cursor after `twdoc_load`; documented in [CHANGELOG.md](../../CHANGELOG.md). Reading from the start of a long file can use **Page Up** / **Home** / navigation as needed.

## Verification

- Import a multi-line file with typewriter on: a block of lines should be visible without arbitrary arrow presses (in addition to BR-001’s redraw fix).

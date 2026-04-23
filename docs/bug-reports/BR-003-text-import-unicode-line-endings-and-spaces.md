# BR-003 — Unicode line endings and spaces mishandled on import and input

**Status:** Fixed  
**Date reported:** 2026-04-19  
**Area:** `DocumentModel.TwDoc.load`, `TwDoc.putc`, `CanvasView` / `CanvasNSView` input

## Summary

- **Line breaks:** Files using only `\n` and `\r\n` are common, but some sources emit **NEL** (U+0085), **line separator** (U+2028), or **paragraph separator** (U+2029). Iterating the string per `Character` or handling only ASCII `\n`/`\r` could drop or mangle line structure.
- **Spaces:** **NBSP** and other Unicode space characters are not ASCII 32; they were skipped or not normalized to a single **cell space** in the grid.
- **Form feed (U+000C):** Must remain a **page** break in the grid, not a generic “newline” for splitting, or multi-page `fullText()` round-trips break.

## Environment

- UTF-8 `.txt` from web, word processors, or PDF paste.
- iOS/macOS `String` and `Character` line-breaking behaviour.

## Steps to reproduce (historical)

1. Save or paste text using U+00A0 as the space between words, or U+2028 as line break.
2. Open in Typewrite: words could run together; lines could merge or miss breaks.

## Root cause

- `load` and `putc` paths filtered too narrowly (e.g. printable ASCII only) or split lines without the full system newline set.
- `NSCharacterSet.newlines` includes U+000C; splitting on that would turn form feeds into “lines” and lose `newPage()` semantics.
- `putc` computed a mapped character `g` for whitespace but (in an earlier revision) could still write the unmapped `c` in insert/typeover paths.

## Fix

- Normalize `\r\n` and lone `\r` to `\n`, then split with a **copy** of the newline set **minus U+000C**, then per-line handling for tab, `newPage` on 0x0C, and Unicode spaces → one ASCII space in the cell.
- `insertPutc` / `typeoverPutc` receive the **normalized** character.
- Keyboard and paste paths on both platforms: treat `Character.isNewline` and `isWhitespace` consistently with the model.

## Verification

- Round-trip: type multi-page content with `fullText`, save, reload; page breaks and line breaks match.
- Import samples with NEL, U+2028, NBSP: layout matches a reference editor (TextEdit) where applicable.

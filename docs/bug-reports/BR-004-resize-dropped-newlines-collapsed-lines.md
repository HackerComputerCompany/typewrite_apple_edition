# BR-004 — `resize` dropped newlines and collapsed lines after load

**Status:** Fixed  
**Date reported:** 2026-04-23  
**Area:** `DocumentModel.TwDoc.resize`, interaction with `CanvasView.recalcLayout` / layout

## Summary

After `load` correctly filled the grid with multiple lines, the first **layout pass** often called `resize` when on-screen column/row counts differed from the model’s defaults. `resize` walked `fullText()` and called `putc` for every character. **`putc` rejects code points outside ASCII 32…126**, so **U+000A** (and other line breaks) were **silently ignored**. All row content was replayed as one continuous stream, wiping line structure. The app looked like “there are no newlines when loading.”

## Environment

- Any multi-line `.txt` after open or import, when `recalcLayout` changes `cols` or `rows` vs the pre-layout `TwDoc` size (common on first layout).

## Steps to reproduce (before fix)

1. Open a file with several lines of text.
2. Observe after the view finishes layout: lines are **merged** into one logical line (wrapping as a single paragraph), or structure is wrong.

## Root cause

1. `fullText()` serializes rows with `\n` between them.
2. `resize` used `for c in text { putc(c) }` with no branch for line breaks.
3. `TwDoc.putc` begins with `guard g.isASCII ... >= 32 ...` — **newline is not passed through**.

## Fix

- In `resize`, treat `\n`, `\r`, and `Character.isNewline` by calling `newline()` before handling printable characters.
- During `resize` (and `load`), force **`insertMode = false`** while replaying so insert semantics do not shift cells on each character.

## Verification

- Multi-line file: open, then rotate or resize window if needed; line breaks match the source.
- Breakpoint or log: `resize` loop should call `newline()` once per inter-row `\n` in `fullText()`.

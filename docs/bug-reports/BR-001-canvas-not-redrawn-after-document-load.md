# BR-001 — Canvas not redrawn after `TwDoc.load`

**Status:** Fixed  
**Date reported:** 2026-04-19  
**Area:** iOS + macOS (`EditorView`, `CanvasRepresentable`, `CanvasView` / `CanvasNSView`)

## Summary

After loading document text (initial `PlainTextDocument` open, or **Import** from the file picker), the character grid was updated in `TwDoc` but the custom canvas sometimes **did not paint** the new content until the user pressed a key (e.g. arrow), which called `setNeedsDisplay` / `needsDisplay` on the next action.

## Environment

- Typewrite Apple Edition, `EditorView` + `CanvasRepresentable`
- iPadOS / macOS, DocumentGroup + `ReferenceFileDocument`

## Steps to reproduce (before fix)

1. Open a non-empty document or use **Import** to load a `.txt` file.
2. Observe the paper area: it may show **previous** or **empty** state until a cursor key or other input triggers a redraw.

## Expected vs actual

- **Expected:** The canvas immediately shows the loaded text.  
- **Actual:** A redraw was missing because `load` is not part of the keyboard / `onTextChange` path that usually invalidates the view.

## Root cause

- `CanvasRepresentable.updateUIView` / `updateNSView` calls `setNeedsDisplay` on each SwiftUI update, but a load in `onAppear` or the file importer **does not** guarantee a follow-up `update*View` in the same turn.
- `TwDoc.load` mutates the model only; it does not notify the `UIView` / `NSView`.

## Fix

- `EditorView.refreshCanvasAfterDocumentLoad()`: `resetCursorBlink()` (which invalidates) immediately and again `DispatchQueue.main.async` so a second pass runs after any pending `layoutSubviews` / `resize` on the grid.
- Call this after `canvas.doc.load` in `onAppear` and after successful file import.

## Verification

- Open a large `.txt` from the picker; text appears without pressing keys.
- Cold launch with a non-empty `document.text`: content is visible on first frame after layout.

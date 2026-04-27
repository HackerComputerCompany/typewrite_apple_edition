// DocumentModel.swift
//
// The character grid document model, ported from the X11 tw_core.c / tw_doc.c.
//
// TwCore is a single page: a flat array of Characters with cursor (cx, cy).
// TwDoc is a multi-page document that wraps TwCore pages, handling page
// breaks, insert/typeover modes, cursor movement, and text I/O.
//
// Key concepts:
//   - Pages are fixed-size grids (cols × rows) — no line wrapping within a row
//   - Typing past the last column wraps to the next row
//   - Typing past the last row creates a new page
//   - Insert mode shifts characters right; typeover overwrites in place
//   - The bell callback fires when the cursor reaches the right margin on
//     typewriter fonts (indices 2-3), matching the X11 bell behaviour
//   - fullText() serializes all pages with form-feed (\u{0C}) separators
//   - load() deserializes text back into the grid, replacing all content

import Foundation
import QuartzCore
import Combine

struct TwCore {
    var cols: Int
    var rows: Int
    var cx: Int = 0
    var cy: Int = 0
    var cells: [TwCell]

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.cells = [TwCell](repeating: .space, count: cols * rows)
    }

    func cell(at col: Int, row: Int) -> TwCell {
        guard col >= 0, col < cols, row >= 0, row < rows else { return .space }
        return cells[row * cols + col]
    }

    mutating func putc(_ c: Character, ink: InkColor) -> (wrapped: Bool, newPageNeeded: Bool) {
        guard cx < cols && cy < rows else { return (false, false) }
        cells[cy * cols + cx] = TwCell(c, ink)
        cx += 1
        if cx >= cols {
            if cy < rows - 1 {
                cx = 0
                cy += 1
                return (true, false)
            } else {
                cx = cols - 1
                return (true, true)
            }
        }
        return (false, false)
    }

    mutating func backspace() {
        if cx > 0 {
            cx -= 1
            cells[cy * cols + cx] = .space
        } else if cy > 0 {
            cy -= 1
            cx = cols - 1
            while cx > 0 && cells[cy * cols + cx].ch == " " {
                cx -= 1
            }
            if cells[cy * cols + cx].ch != " " { cx += 1 }
        }
    }

    mutating func newline() {
        cx = 0
        if cy < rows - 1 {
            cy += 1
        }
    }

    mutating func clear() {
        cells = [TwCell](repeating: .space, count: cols * rows)
        cx = 0
        cy = 0
    }

    func rowString(_ row: Int) -> String {
        guard row >= 0, row < rows else { return "" }
        let start = row * cols
        return String(cells[start..<(start + cols)].map(\.ch))
    }

    /// Screen row in row-major order (one page).
    func rowTwCells(_ row: Int) -> [TwCell] {
        guard row >= 0, row < rows else { return [] }
        let start = row * cols
        return Array(cells[start..<(start + cols)])
    }
}

class TwDoc {
    var pages: [TwCore]
    var curPage: Int = 0
    var insertMode: Bool = false
    var wordWrap: Bool = true
    /// Ink for the next typed / pasted printable character.
    var currentInk: InkColor = .ink

    var cols: Int
    var rows: Int

    init(cols: Int = 58, rows: Int = 24) {
        self.cols = cols
        self.rows = rows
        self.pages = [TwCore(cols: cols, rows: rows)]
    }

    var currentPage: TwCore {
        get { pages[curPage] }
        set { pages[curPage] = newValue }
    }

    func putc(_ c: Character) {
        putGlyph(c, ink: currentInk)
    }

    /// Puts a printable cell with an explicit ink (used when replaying `resize` and plain-text `load`).
    func putGlyph(_ c: Character, ink: InkColor) {
        if c == "\t" { return }
        let g: Character = (c.isWhitespace && !c.isNewline) ? " " : c
        guard g.isASCII, g.asciiValue! >= 32, g.asciiValue! <= 126 else { return }
        let page = pages[curPage]
        let isLastRow = page.cy >= rows - 1
        if insertMode {
            insertPutc(TwCell(g, ink), isLastRow: isLastRow)
        } else {
            typeoverPutc(TwCell(g, ink), isLastRow: isLastRow)
        }
    }

    var bellHandler: (() -> Void)?

    private func withBellSuppressed<T>(_ body: () throws -> T) rethrows -> T {
        let saved = bellHandler
        bellHandler = nil
        defer { bellHandler = saved }
        return try body()
    }

    private func rowAllSpaces(_ tw: TwCore, row: Int) -> Bool {
        guard row >= 0, row < rows else { return true }
        let base = row * cols
        for i in 0..<cols where tw.cells[base + i].ch != " " { return false }
        return true
    }

    /// Port of `twdoc_try_soft_wrap`: full line, break after last ASCII space when the next row is empty
    /// (or when wrapping from the last row, advance to the next page like `twdoc_newline`).
    private func trySoftWrap() -> Bool {
        guard wordWrap else { return false }
        guard pages[curPage].cx >= cols else { return false }

        let cy = pages[curPage].cy
        let rowBase = cy * cols

        var lastNs = -1
        for i in stride(from: cols - 1, through: 0, by: -1) {
            if pages[curPage].cells[rowBase + i].ch != " " {
                lastNs = i
                break
            }
        }
        guard lastNs >= 0 else { return false }

        var sp = -1
        for i in stride(from: lastNs - 1, through: 0, by: -1) {
            if pages[curPage].cells[rowBase + i].ch == " " {
                sp = i
                break
            }
        }
        guard sp >= 0 else { return false }

        let tailLen = lastNs - sp
        guard tailLen > 0, tailLen <= cols else { return false }

        if cy < rows - 1 {
            guard rowAllSpaces(pages[curPage], row: cy + 1) else { return false }
        }

        var buf: [TwCell] = []
        buf.reserveCapacity(tailLen)
        for i in 0..<tailLen {
            buf.append(pages[curPage].cells[rowBase + sp + 1 + i])
        }
        for i in (sp + 1)..<cols {
            pages[curPage].cells[rowBase + i] = .space
        }

        newline()
        var tw = pages[curPage]
        let nrow = tw.cy * cols
        for i in 0..<cols {
            tw.cells[nrow + i] = .space
        }
        for i in 0..<tailLen {
            tw.cells[nrow + i] = buf[i]
        }
        tw.cx = tailLen
        pages[curPage] = tw
        return true
    }

    private func typeoverBellIfNeeded(oldCy: Int, isLastRow: Bool) {
        let p = pages[curPage]
        if isLastRow && oldCy >= rows - 1 && p.cy >= rows - 1 && p.cx <= 1 {
            bellHandler?()
            newPage()
        }
    }

    private func typeoverPutc(_ cell: TwCell, isLastRow: Bool) {
        let oldCy = pages[curPage].cy
        var tw = pages[curPage]
        guard tw.cx < cols && tw.cy < rows else { return }
        tw.cells[tw.cy * cols + tw.cx] = cell
        tw.cx += 1
        pages[curPage] = tw

        if pages[curPage].cx >= cols {
            if trySoftWrap() {
                typeoverBellIfNeeded(oldCy: oldCy, isLastRow: isLastRow)
                return
            }
            var t = pages[curPage]
            if t.cy < rows - 1 {
                t.cx = 0
                t.cy += 1
                pages[curPage] = t
            } else {
                t.cx = cols - 1
                pages[curPage] = t
            }
        }
        typeoverBellIfNeeded(oldCy: oldCy, isLastRow: isLastRow)
    }

    private func insertPutc(_ cell: TwCell, isLastRow: Bool) {
        let p = pages[curPage]
        let row = p.cy
        let col = p.cx
        if col < cols - 1 {
            for x in stride(from: cols - 2, through: col, by: -1) {
                pages[curPage].cells[row * cols + x + 1] = pages[curPage].cells[row * cols + x]
            }
        }
        pages[curPage].cells[row * cols + col] = cell
        pages[curPage].cx = col + 1
        if pages[curPage].cx >= cols {
            if trySoftWrap() {
                return
            }
            if isLastRow {
                newPage()
            } else {
                pages[curPage].cx = 0
                pages[curPage].cy += 1
            }
        }
    }

    func newline() {
        if pages[curPage].cy >= rows - 1 {
            newPage()
        } else {
            pages[curPage].newline()
        }
    }

    func backspace() {
        pages[curPage].backspace()
    }

    func delete() {
        let p = pages[curPage]
        let row = p.cy
        let col = p.cx
        for x in col..<(cols - 1) {
            pages[curPage].cells[row * cols + x] = pages[curPage].cells[row * cols + x + 1]
        }
        pages[curPage].cells[row * cols + cols - 1] = .space
    }

    func moveLeft() {
        let p = pages[curPage]
        if p.cx > 0 {
            pages[curPage].cx -= 1
        } else if p.cy > 0 {
            pages[curPage].cy -= 1
            pages[curPage].cx = cols - 1
        } else if curPage > 0 {
            curPage -= 1
            pages[curPage].cx = cols - 1
            pages[curPage].cy = rows - 1
        }
    }

    func moveRight() {
        let p = pages[curPage]
        if p.cx < cols - 1 {
            pages[curPage].cx += 1
        } else if p.cy < rows - 1 {
            pages[curPage].cy += 1
            pages[curPage].cx = 0
        } else if curPage < pages.count - 1 {
            curPage += 1
            pages[curPage].cx = 0
            pages[curPage].cy = 0
        }
    }

    func moveUp() {
        let p = pages[curPage]
        if p.cy > 0 {
            pages[curPage].cy -= 1
        } else if curPage > 0 {
            curPage -= 1
            pages[curPage].cy = rows - 1
        }
    }

    func moveDown() {
        let p = pages[curPage]
        if p.cy < rows - 1 {
            pages[curPage].cy += 1
        } else if curPage < pages.count - 1 {
            curPage += 1
            pages[curPage].cy = 0
        }
    }

    func moveHome() {
        pages[curPage].cx = 0
    }

    func moveEnd() {
        let p = pages[curPage]
        var lastNonSpace = -1
        for x in 0..<cols {
            if p.cells[p.cy * cols + x].ch != " " { lastNonSpace = x }
        }
        if lastNonSpace == -1 {
            pages[curPage].cx = 0
        } else {
            pages[curPage].cx = min(lastNonSpace + 1, cols - 1)
        }
    }

    func pageUp() {
        if curPage > 0 { curPage -= 1 }
    }

    func pageDown() {
        if curPage < pages.count - 1 { curPage += 1 }
    }

    private func newPage() {
        let newP = TwCore(cols: cols, rows: rows)
        pages.insert(newP, at: curPage + 1)
        curPage += 1
    }

    /// Full grid, row-major: one op per cell, newlines between rows, form feed between pages.
    /// Matches a global **flat cell index** so cursor restoration is stable across column/row changes (unlike `fullText()` rtrim).
    private static func buildResizeOps(pages: [TwCore], cols: Int, rows: Int) -> [TwResizeOp] {
        var out: [TwResizeOp] = []
        for (i, page) in pages.enumerated() {
            if i > 0 { out.append(.formFeed) }
            for row in 0..<rows {
                for col in 0..<cols {
                    let cell = page.cells[row * cols + col]
                    out.append(.glyph(cell.ch, cell.ink))
                }
                if row < rows - 1 { out.append(.newline) }
            }
        }
        return out
    }

    /// Linear index of the cursor’s “next write” cell in row-major order across all pages (same order as `buildResizeOps` glyphs).
    private static func flatCellIndexBeforeWrite(curPage: Int, cx: Int, cy: Int, cols: Int, rows: Int) -> Int {
        curPage * (rows * cols) + cy * cols + cx
    }

    func resize(cols newCols: Int, rows newRows: Int) {
        guard newCols > 0, newRows > 0 else { return }
        let oldPages = pages
        let oldCols = cols
        let oldRows = rows
        let oldCurPage = curPage
        let oldCy = oldPages[oldCurPage].cy
        let oldCx = oldPages[oldCurPage].cx

        /// How many `putGlyph` calls match the cursor position in the **old** grid stream (full rows, no rtrim).
        let targetGlyphCount = Self.flatCellIndexBeforeWrite(curPage: oldCurPage, cx: oldCx, cy: oldCy, cols: oldCols, rows: oldRows)

        let ops = Self.buildResizeOps(pages: oldPages, cols: oldCols, rows: oldRows)

        let savedInsert = insertMode
        let savedInk = currentInk
        let savedWordWrap = wordWrap
        insertMode = false
        wordWrap = false
        defer { insertMode = savedInsert; currentInk = savedInk; wordWrap = savedWordWrap }

        cols = newCols
        rows = newRows
        pages = [TwCore(cols: newCols, rows: newRows)]
        curPage = 0
        var glyphCount = 0
        var targetCx = 0
        var targetCy = 0
        var targetPage = 0
        var snapped = false
        if targetGlyphCount == 0 {
            targetCx = 0
            targetCy = 0
            targetPage = 0
            snapped = true
        }

        withBellSuppressed {
            for op in ops {
                switch op {
                case .formFeed:
                    newPage()
                    pages[curPage].cx = 0
                    pages[curPage].cy = 0
                case .newline:
                    newline()
                case .glyph(let c, let ink):
                    putGlyph(c, ink: ink)
                    glyphCount += 1
                    if glyphCount == targetGlyphCount {
                        targetCx = pages[curPage].cx
                        targetCy = pages[curPage].cy
                        targetPage = curPage
                        snapped = true
                    }
                }
            }
        }
        if pages.count == 1 && pages[0].cells.allSatisfy({ $0 == .space }) {
            curPage = 0
            pages[0].cx = 0
            pages[0].cy = 0
        } else if snapped {
            curPage = min(targetPage, pages.count - 1)
            pages[curPage].cx = targetCx
            pages[curPage].cy = targetCy
        } else {
            // Empty stream or index past end — park at end or (0,0)
            if glyphCount == 0 {
                curPage = 0
                pages[0].cx = 0
                pages[0].cy = 0
            } else {
                positionCursorAtDocumentEnd()
            }
        }
    }

    func fullText() -> String {
        var result = ""
        for (i, page) in pages.enumerated() {
            if i > 0 { result += "\u{0C}" }
            for row in 0..<page.rows {
                let line = page.rowString(row)
                result += line.rtrim(" ")
                if row < page.rows - 1 { result += "\n" }
            }
        }
        return result
    }

    /// Line breaks for loading plain text, matching `NSCharacterSet.newlines` (NEL, U+2028, U+2029, …) but **not** form feed (U+000C) — that stays in-band as a page break (`newPage()`), same as `fullText()` and X11.
    private static var textLoadLineBreakSet: CharacterSet = {
        let m = (NSCharacterSet.newlines as NSCharacterSet).mutableCopy() as! NSMutableCharacterSet
        m.removeCharacters(in: "\u{0C}")
        return m as CharacterSet
    }()

    func load(_ text: String) {
        // Insert mode would shift the grid on each `putc` and destroy imported layout.
        let savedInsert = insertMode
        let savedInk = currentInk
        insertMode = false
        currentInk = .ink
        defer { insertMode = savedInsert; currentInk = savedInk }

        // Normalize common line endings, then split on the full newline set (per-`Character` iteration is unreliable for NEL, LS, PS, etc.).
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.components(separatedBy: Self.textLoadLineBreakSet)

        pages = [TwCore(cols: cols, rows: rows)]
        curPage = 0

        withBellSuppressed {
            for (lineIndex, line) in lines.enumerated() {
                for c in line {
                    if c == "\u{0C}" {
                        newPage()
                        pages[curPage].cx = 0
                        pages[curPage].cy = 0
                        continue
                    }
                    if c == "\t" {
                        for _ in 0..<4 { putGlyph(" ", ink: .ink) }
                        continue
                    }
                    if c.isNewline {
                        newline()
                        continue
                    }
                    if c.isWhitespace, !c.isNewline {
                        putGlyph(" ", ink: .ink)
                        continue
                    }
                    if c.isASCII, let ascii = c.asciiValue, ascii >= 32, ascii <= 126 {
                        putGlyph(c, ink: .ink)
                    }
                }
                if lineIndex < lines.count - 1 {
                    newline()
                }
            }
        }
        // Leave the cursor at the end of the loaded text (do not force 0,0 on page 0). Matching X11’s twdoc_load
        // would pin to the top of page 0, but with typewriter rendering that made multi-line opens look “empty”
        // until the cursor moved — only one buffer row is visible when cy == 0. End-of-text cursor maps the viewport correctly.
    }

    func countWords() -> Int {
        var count = 0
        for page in pages {
            for row in 0..<page.rows {
                let line = page.rowString(row)
                count += line.split(whereSeparator: { $0.isWhitespace }).count
            }
        }
        return count
    }

    /// Places the cursor on the last page just after the last non-space character (typical end-of-typing), or `(0,0)` if empty.
    func positionCursorAtDocumentEnd() {
        for pi in (0..<pages.count).reversed() {
            curPage = pi
            let page = pages[pi]
            for r in (0..<rows).reversed() {
                let base = r * cols
                for c in (0..<cols).reversed() {
                    if page.cells[base + c].ch != " " {
                        if c < cols - 1 {
                            pages[curPage].cx = c + 1
                            pages[curPage].cy = r
                        } else {
                            if r < rows - 1 {
                                pages[curPage].cx = 0
                                pages[curPage].cy = r + 1
                            } else {
                                pages[curPage].cx = c
                                pages[curPage].cy = r
                            }
                        }
                        return
                    }
                }
            }
        }
        if !pages.isEmpty {
            curPage = 0
            pages[0].cx = 0
            pages[0].cy = 0
        }
    }
}

extension String {
    func rtrim(_ char: Character) -> String {
        var s = self
        while s.last == char { s.removeLast() }
        return s
    }
}

// MARK: - Session metrics (matches Typewrite X11 status pulse / typing pace)

enum TypingSessionInput: Sendable {
    case printable
    case tab
    case newline
}

/// Tracks session “typing units” and a gap-based typing pace (EMA), like `TypingPace` in `main_x11.c`.
@MainActor
final class WritingSessionTracker: ObservableObject {
    private(set) var sessionTypingUnits: UInt64 = 0
    private var lastCharMonoMs: Double = 0
    private var emaMsPerChar: Double = 0

    private let pauseMs: Double = 2800
    private let minGapMs: Double = 40
    private let gapCapMs: Double = 720

    func resetSession() {
        sessionTypingUnits = 0
        lastCharMonoMs = 0
        emaMsPerChar = 0
    }

    func note(_ input: TypingSessionInput) {
        switch input {
        case .printable: sessionTypingUnits += 1
        case .tab: sessionTypingUnits += 4
        case .newline: sessionTypingUnits += 1
        }
        recordPaceSample()
    }

    private func recordPaceSample() {
        let nowMs = CACurrentMediaTime() * 1000.0
        defer { lastCharMonoMs = nowMs }
        guard lastCharMonoMs > 0 else { return }
        let dt = nowMs - lastCharMonoMs
        guard dt >= minGapMs, dt < pauseMs else { return }
        let dtf = min(dt, gapCapMs)
        if emaMsPerChar <= 0 {
            emaMsPerChar = dtf
        } else {
            emaMsPerChar = 0.88 * emaMsPerChar + 0.12 * dtf
        }
    }

    func wpmRounded() -> UInt {
        guard emaMsPerChar > 0 else { return 0 }
        let w = 12000.0 / emaMsPerChar
        if w < 0 { return 0 }
        if w > 999 { return 999 }
        return UInt(w + 0.5)
    }

    /// Same fields as X11 `format_status_pulse_toast`.
    func statusPulseMessage(for doc: TwDoc) -> String {
        let wpm = wpmRounded()
        let sessWords = (sessionTypingUnits + 4) / 5
        let docWords = UInt(max(0, doc.countWords()))
        let tf = DateFormatter()
        tf.locale = Locale.current
        tf.dateFormat = "HH:mm"
        let timestr = tf.string(from: Date())
        return "\(wpm) wpm | session \(sessWords) words | doc \(docWords) words | \(timestr)"
    }

    /// Persisted inside the binary `.twd` bundle.
    func sessionMetadataForArchive() -> TwSessionMetadata {
        TwSessionMetadata(sessionTypingUnits: sessionTypingUnits, emaMsPerChar: emaMsPerChar, savedAt: Date())
    }

    func applySessionMetadata(_ m: TwSessionMetadata) {
        sessionTypingUnits = m.sessionTypingUnits
        emaMsPerChar = m.emaMsPerChar
    }
}
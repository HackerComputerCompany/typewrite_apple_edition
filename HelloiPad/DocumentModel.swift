import Foundation

struct TwCore {
    var cols: Int
    var rows: Int
    var cx: Int = 0
    var cy: Int = 0
    var cells: [Character]

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.cells = [Character](repeating: " ", count: cols * rows)
    }

    func cell(at col: Int, row: Int) -> Character {
        guard col >= 0, col < cols, row >= 0, row < rows else { return " " }
        return cells[row * cols + col]
    }

    mutating func putc(_ c: Character) -> (wrapped: Bool, newPageNeeded: Bool) {
        guard cx < cols && cy < rows else { return (false, false) }
        cells[cy * cols + cx] = c
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
            cells[cy * cols + cx] = " "
        } else if cy > 0 {
            cy -= 1
            cx = cols - 1
            while cx > 0 && cells[cy * cols + cx] == " " {
                cx -= 1
            }
            if cells[cy * cols + cx] != " " { cx += 1 }
        }
    }

    mutating func newline() {
        cx = 0
        if cy < rows - 1 {
            cy += 1
        }
    }

    mutating func clear() {
        cells = [Character](repeating: " ", count: cols * rows)
        cx = 0
        cy = 0
    }

    func rowString(_ row: Int) -> String {
        guard row >= 0, row < rows else { return "" }
        let start = row * cols
        return String(cells[start..<(start + cols)])
    }
}

class TwDoc {
    var pages: [TwCore]
    var curPage: Int = 0
    var insertMode: Bool = false
    var wordWrap: Bool = true

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
        guard c.isASCII, c.asciiValue! >= 32, c.asciiValue! <= 126 else { return }
        let page = pages[curPage]
        let isLastCol = page.cx >= cols - 1
        let isLastRow = page.cy >= rows - 1

        if insertMode {
            insertPutc(c, isLastCol: isLastCol, isLastRow: isLastRow)
        } else {
            typeoverPutc(c, isLastCol: isLastCol, isLastRow: isLastRow)
        }
    }

    var bellHandler: (() -> Void)?

    private func typeoverPutc(_ c: Character, isLastCol: Bool, isLastRow: Bool) {
        let oldCy = pages[curPage].cy
        pages[curPage].putc(c)
        if isLastRow && oldCy >= rows - 1 && pages[curPage].cy >= rows - 1 && pages[curPage].cx <= 1 {
            bellHandler?()
            newPage()
        }
    }

    private func insertPutc(_ c: Character, isLastCol: Bool, isLastRow: Bool) {
        let p = pages[curPage]
        let row = p.cy
        let col = p.cx
        if col < cols - 1 {
            for x in stride(from: cols - 2, through: col, by: -1) {
                pages[curPage].cells[row * cols + x + 1] = pages[curPage].cells[row * cols + x]
            }
        }
        pages[curPage].cells[row * cols + col] = c
        pages[curPage].cx = col + 1
        if pages[curPage].cx >= cols {
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
        pages[curPage].cells[row * cols + cols - 1] = " "
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
            if p.cells[p.cy * cols + x] != " " { lastNonSpace = x }
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

    func resize(cols newCols: Int, rows newRows: Int) {
        let text = fullText()
        let oldPage = curPage
        let oldCy = pages[curPage].cy
        let oldCx = pages[curPage].cx
        let offset = oldCy * cols + oldCx

        cols = newCols
        rows = newRows
        pages = [TwCore(cols: newCols, rows: newRows)]
        curPage = 0
        var charCount = 0
        var targetCx = 0
        var targetCy = 0
        var targetPage = 0
        for c in text {
            if c == "\u{0C}" {
                newPage()
                pages[curPage].cx = 0
                pages[curPage].cy = 0
                continue
            }
            putc(c)
            charCount += 1
            if charCount == offset || (charCount > offset && targetPage == 0) {
                targetCx = pages[curPage].cx
                targetCy = pages[curPage].cy
                targetPage = curPage
            }
        }
        if pages.count == 1 && pages[0].cells.allSatisfy({ $0 == " " }) {
            curPage = 0
            pages[0].cx = 0
            pages[0].cy = 0
        } else {
            curPage = min(targetPage, pages.count - 1)
            pages[curPage].cx = targetCx
            pages[curPage].cy = targetCy
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

    func load(_ text: String) {
        pages = [TwCore(cols: cols, rows: rows)]
        curPage = 0
        for c in text {
            if c == "\u{0C}" {
                newPage()
                pages[curPage].cx = 0
                pages[curPage].cy = 0
                continue
            }
            if c == "\n" { newline(); continue }
            if c == "\t" {
                for _ in 0..<4 { putc(" ") }
                continue
            }
            if c.isASCII, let ascii = c.asciiValue, ascii >= 32, ascii <= 126 {
                putc(c)
            }
        }
        curPage = 0
        pages[curPage].cx = 0
        pages[curPage].cy = 0
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
}

extension String {
    func rtrim(_ char: Character) -> String {
        var s = self
        while s.last == char { s.removeLast() }
        return s
    }
}
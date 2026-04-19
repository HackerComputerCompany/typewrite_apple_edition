// CanvasNSView.swift — AppKit counterpart to typewrite_apple_edition/CanvasView.swift.
// Logic is kept in sync deliberately; consider extracting shared drawing later.

import AppKit

final class CanvasNSView: NSView {

    private let settings = SettingsStore.shared
    private let fontRegistry = FontRegistry.shared
    private let soundManager = SoundManager.shared

    var doc = TwDoc(cols: 58, rows: 24)
    var onTextChange: (() -> Void)?
    var onTypingSessionInput: ((TypingSessionInput) -> Void)?
    var onStatusPulseShortcut: (() -> Void)?
    var onToggleSoundsShortcut: (() -> Void)?
    var onDocInfoUpdate: ((Int, Int) -> Void)?

    private var blinkTimer: Timer?
    private var cursorVisible = true
    private var lastBlinkTime: CFTimeInterval = 0
    private let blinkInterval: CFTimeInterval = 0.5

    private var pageMargins: Bool = true
    private var colsMargined: Int = 58
    private var typewriterView: Bool = true
    private var gutterMode: GutterMode = .off
    private var insertMode: Bool = false
    private var fontIndex: Int = 2

    struct ViewLayout {
        var marginLeft: CGFloat = 0
        var marginRight: CGFloat = 0
        var marginTop: CGFloat = 0
        var marginBottom: CGFloat = 0
        var gutterWidth: CGFloat = 0
        var paperX: CGFloat = 0
        var paperY: CGFloat = 0
        var paperW: CGFloat = 0
        var paperH: CGFloat = 0
        var textX0: CGFloat = 0
        var textY0: CGFloat = 0
        var cols: Int = 58
        var rows: Int = 24
    }

    /// Layout metrics (renamed from `layout` to avoid clashing with `NSView.layout()`).
    private(set) var viewLayout = ViewLayout()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        doc.bellHandler = { [weak self] in
            self?.soundManager.playBell(for: self?.fontIndex ?? 2)
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        doc.bellHandler = { [weak self] in
            self?.soundManager.playBell(for: self?.fontIndex ?? 2)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            blinkTimer?.invalidate()
            blinkTimer = nil
            return
        }
        if blinkTimer == nil {
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.tickBlink()
            }
            if let blinkTimer {
                RunLoop.main.add(blinkTimer, forMode: .common)
            }
        }
    }

    override func removeFromSuperview() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        super.removeFromSuperview()
    }

    private func tickBlink() {
        let now = CACurrentMediaTime()
        let mode = settings.cursorMode
        if mode.isBlink {
            if now - lastBlinkTime > blinkInterval {
                cursorVisible.toggle()
                lastBlinkTime = now
                needsDisplay = true
            }
        } else {
            if !cursorVisible {
                cursorVisible = true
                needsDisplay = true
            }
        }
    }

    func resetCursorBlink() {
        cursorVisible = true
        lastBlinkTime = CACurrentMediaTime()
        needsDisplay = true
    }

    func updateFromSettings() {
        fontIndex = settings.fontIndex
        pageMargins = settings.pageMargins
        colsMargined = settings.colsMargined
        typewriterView = settings.typewriterView
        gutterMode = settings.gutterMode
        insertMode = settings.insertMode
        doc.insertMode = insertMode
        doc.wordWrap = settings.wordWrap
        recalcLayout()
        needsDisplay = true
    }

    private func lineNumberGutterWidth(cellW: CGFloat) -> CGFloat {
        switch gutterMode {
        case .off:
            return 0
        case .ascending, .descending:
            var g = cellW * 4 + 12
            if g < cellW * 5 { g = cellW * 5 }
            if g < 28 { g = 28 }
            return g
        }
    }

    private func letterMarginPx(boundsW: CGFloat, boundsH: CGFloat, cellW: CGFloat, cellH: CGFloat, gutter: CGFloat) -> CGFloat {
        guard boundsW > 0, boundsH > 0 else { return 0 }
        var marginPx: CGFloat = 96
        if marginPx > boundsW / 6 { marginPx = floor(boundsW / 6) }
        if marginPx > boundsH / 6 { marginPx = floor(boundsH / 6) }
        if marginPx < 16 { marginPx = 16 }
        while marginPx > 0 && (boundsW < 2 * marginPx + gutter + cellW || boundsH < 2 * marginPx + cellH) {
            marginPx -= 2
        }
        if marginPx < 0 { marginPx = 0 }
        return marginPx
    }

    func recalcLayout() {
        let twFont = fontRegistry.font(at: fontIndex)
        let cellW = twFont.cellWidth
        let cellH = twFont.cellHeight

        let boundsW = bounds.width
        let boundsH = bounds.height
        guard boundsW > 0, boundsH > 0 else { return }

        let gutter = lineNumberGutterWidth(cellW: cellW)

        let paperX: CGFloat
        let paperY: CGFloat
        let paperW: CGFloat
        let paperH: CGFloat
        let textX0: CGFloat
        let textY0: CGFloat
        let marginLeft: CGFloat
        let marginRight: CGFloat
        let marginTop: CGFloat
        let marginBottom: CGFloat
        let targetCols: Int
        let targetRows: Int

        if pageMargins {
            let marginPx = letterMarginPx(boundsW: boundsW, boundsH: boundsH, cellW: cellW, cellH: cellH, gutter: gutter)
            let maxColsFit = max(1, Int((boundsW - 2 * marginPx - gutter) / cellW))
            targetCols = min(colsMargined, maxColsFit)
            targetRows = max(1, Int((boundsH - 2 * marginPx) / cellH))

            paperW = 2 * marginPx + gutter + CGFloat(targetCols) * cellW
            paperH = 2 * marginPx + CGFloat(targetRows) * cellH
            paperX = (boundsW > paperW) ? (boundsW - paperW) / 2 : 0
            paperY = (boundsH > paperH) ? (boundsH - paperH) / 2 : 0
            textX0 = paperX + marginPx + gutter
            textY0 = paperY + marginPx
            marginLeft = marginPx
            marginRight = marginPx
            marginTop = marginPx
            marginBottom = marginPx
        } else {
            let s = safeAreaInsets
            let minPad: CGFloat = 20
            let padL = max(minPad, s.left)
            let padR = max(minPad, s.right)
            let padT = max(minPad, s.top)
            let padB = max(minPad, s.bottom)
            let innerW = boundsW - padL - padR
            let innerH = boundsH - padT - padB

            let maxCols = min(80, max(1, Int((innerW - gutter) / cellW)))
            targetCols = maxCols
            targetRows = max(1, Int(innerH / cellH))

            paperW = gutter + CGFloat(targetCols) * cellW
            paperH = CGFloat(targetRows) * cellH
            paperX = padL + max(0, (innerW - paperW) / 2)
            paperY = padT + max(0, (innerH - paperH) / 2)
            textX0 = paperX + gutter
            textY0 = paperY
            marginLeft = 0
            marginRight = 0
            marginTop = 0
            marginBottom = 0
        }

        viewLayout = ViewLayout(
            marginLeft: marginLeft,
            marginRight: marginRight,
            marginTop: marginTop,
            marginBottom: marginBottom,
            gutterWidth: gutter,
            paperX: paperX,
            paperY: paperY,
            paperW: paperW,
            paperH: paperH,
            textX0: textX0,
            textY0: textY0,
            cols: targetCols,
            rows: targetRows
        )

        if doc.cols != targetCols || doc.rows != targetRows {
            doc.resize(cols: targetCols, rows: targetRows)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recalcLayout()
    }

    override func layout() {
        super.layout()
        // macOS NSView has no safeAreaInsetsDidChange; layout runs when safe areas / sizing change.
        recalcLayout()
    }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func claimFocus() {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.control) {
            handleCtrlKey(chars: event.charactersIgnoringModifiers ?? "")
            return
        }
        if flags.contains(.command) {
            handleCmdKey(chars: event.charactersIgnoringModifiers ?? "")
            return
        }

        switch event.keyCode {
        case 51: handleBackspace(); return
        case 117: handleDelete(); return
        case 36, 76: handleEnter(); return
        case 48: soundManager.playKey(for: fontIndex); tabInsert(); return
        case 114: toggleInsertMode(); return
        case 101: // F9 — cycle status check-in interval (X11)
            onStatusPulseShortcut?()
            needsDisplay = true
            return
        case 111: // F12 — toggle sounds
            onToggleSoundsShortcut?()
            needsDisplay = true
            return
        default: break
        }

        if let special = event.specialKey {
            switch special {
            case .upArrow: doc.moveUp(); resetCursorBlink(); needsDisplay = true; return
            case .downArrow: doc.moveDown(); resetCursorBlink(); needsDisplay = true; return
            case .leftArrow: doc.moveLeft(); resetCursorBlink(); needsDisplay = true; return
            case .rightArrow: doc.moveRight(); resetCursorBlink(); needsDisplay = true; return
            case .home: doc.moveHome(); resetCursorBlink(); needsDisplay = true; return
            case .end: doc.moveEnd(); resetCursorBlink(); needsDisplay = true; return
            case .pageUp: doc.pageUp(); resetCursorBlink(); needsDisplay = true; return
            case .pageDown: doc.pageDown(); resetCursorBlink(); needsDisplay = true; return
            case .deleteForward: handleDelete(); return
            case .delete: handleBackspace(); return
            case .carriageReturn, .newline: handleEnter(); return
            case .tab: soundManager.playKey(for: fontIndex); tabInsert(); return
            case .insert: toggleInsertMode(); return
            default: break
            }
        }

        if let s = event.characters, let c = s.first {
            if c == "\u{7f}" { handleDelete(); return }
            if c == "\u{8}" { handleBackspace(); return }
            if c == "\n" || c == "\r" { handleEnter(); return }
            if c == "\t" { soundManager.playKey(for: fontIndex); tabInsert(); return }
            if c.isASCII, let ascii = c.asciiValue, ascii >= 32, ascii < 127 {
                typeCharacter(c)
                return
            }
        }

        super.keyDown(with: event)
    }

    func insertCharacter(_ c: Character) {
        if c == "\n" || c == "\r" {
            handleEnter()
        } else if c == "\t" {
            soundManager.playKey(for: fontIndex)
            tabInsert()
        } else if c.isASCII, let ascii = c.asciiValue, ascii >= 32, ascii < 127 {
            typeCharWithSound(c)
        }
    }

    private func typeCharacter(_ c: Character) {
        if c == "\n" || c == "\r" {
            handleEnter()
        } else if c == "\t" {
            soundManager.playKey(for: fontIndex)
            tabInsert()
        } else {
            typeCharWithSound(c)
        }
    }

    private func typeCharWithSound(_ c: Character) {
        onTypingSessionInput?(.printable)
        soundManager.playKey(for: fontIndex)
        if fontIndex == 2 || fontIndex == 3 {
            let p = doc.pages[doc.curPage]
            if p.cx >= doc.cols - 1 {
                soundManager.playBell(for: fontIndex)
            }
        }
        doc.putc(c)
        resetCursorBlink()
        onTextChange?()
        needsDisplay = true
    }

    private func handleEnter() {
        onTypingSessionInput?(.newline)
        soundManager.playCarriage(for: fontIndex)
        doc.newline()
        resetCursorBlink()
        onTextChange?()
        needsDisplay = true
    }

    private func handleBackspace() {
        soundManager.playDelete(for: fontIndex)
        doc.backspace()
        resetCursorBlink()
        onTextChange?()
        needsDisplay = true
    }

    private func handleDelete() {
        soundManager.playDelete(for: fontIndex)
        doc.delete()
        resetCursorBlink()
        onTextChange?()
        needsDisplay = true
    }

    private func toggleInsertMode() {
        insertMode.toggle()
        settings.insertMode = insertMode
        resetCursorBlink()
        needsDisplay = true
    }

    private func handleCtrlKey(chars: String) {
        switch chars.lowercased() {
        case "q", "x": onTextChange?(); return
        case "s": onTextChange?(); return
        default: break
        }
    }

    private func handleCmdKey(chars: String) {
        switch chars.lowercased() {
        case "s": onTextChange?()
        default: break
        }
    }

    private func tabInsert() {
        onTypingSessionInput?(.tab)
        for _ in 0..<4 { doc.putc(" ") }
        resetCursorBlink()
        onTextChange?()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let theme = settings.theme
        let twFont = fontRegistry.font(at: fontIndex)

        if pageMargins {
            ctx.setFillColor(theme.surround.cgColor)
            ctx.fill(bounds)

            let paperRect = CGRect(x: viewLayout.paperX, y: viewLayout.paperY,
                                   width: viewLayout.paperW, height: viewLayout.paperH)
            ctx.setFillColor(theme.paper.cgColor)
            ctx.fill(paperRect)
        } else {
            ctx.saveGState()
            ctx.setBlendMode(.copy)
            ctx.setFillColor(NSColor.clear.cgColor)
            ctx.fill(bounds)
            ctx.restoreGState()

            let paperRect = CGRect(x: viewLayout.paperX, y: viewLayout.paperY,
                                   width: viewLayout.paperW, height: viewLayout.paperH)
            ctx.setFillColor(theme.paper.cgColor)
            ctx.fill(paperRect)
        }

        if pageMargins && typewriterView {
            let topStripH = viewLayout.textY0 - viewLayout.paperY
            if topStripH > 0 {
                ctx.setFillColor(theme.surround.cgColor)
                ctx.fill(CGRect(x: viewLayout.paperX, y: viewLayout.paperY,
                                width: viewLayout.paperW, height: topStripH))
            }
        }

        drawCells(ctx: ctx, font: twFont, theme: theme)
        if pageMargins && typewriterView {
            drawTypewriterFloatingMarginBand(ctx: ctx, font: twFont, theme: theme)
        }
        drawCursor(ctx: ctx, font: twFont, theme: theme)
        drawTypewriterRule(ctx: ctx, font: twFont)
        drawPageFooter(ctx: ctx, font: twFont, theme: theme)
    }

    private func drawCells(ctx: CGContext, font: TypewriterFont, theme: PaperTheme) {
        let page = doc.pages[doc.curPage]
        let cellW = font.cellWidth
        let cellH = font.cellHeight

        let fgColor = theme.ink.cgColor
        let bgColor = theme.paper.cgColor

        let viewRows = min(page.rows, viewLayout.rows)
        let blankRowColor = pageMargins ? theme.surround.cgColor : theme.paper.cgColor

        for row in 0..<viewRows {
            let bufferRow: Int
            if typewriterView {
                bufferRow = typewriterBufferRow(for: row, cursorY: page.cy, viewRows: viewRows)
            } else {
                bufferRow = row
            }

            let rowY = viewLayout.textY0 + CGFloat(row) * cellH
            if typewriterView && bufferRow < 0 {
                ctx.setFillColor(blankRowColor)
                ctx.fill(CGRect(x: viewLayout.paperX, y: rowY, width: viewLayout.paperW, height: cellH))
                continue
            }

            guard bufferRow < page.rows else { continue }

            if gutterMode != .off {
                let lineNum: Int
                switch gutterMode {
                case .ascending: lineNum = bufferRow + 1
                case .descending: lineNum = page.rows - bufferRow
                case .off: lineNum = 0
                }
                let numStr = String(format: "%5d", lineNum)
                let gutterX = viewLayout.textX0 - cellW * 5
                let gutterY = rowY
                drawString(ctx: ctx, font: font, string: numStr, x: gutterX, y: gutterY,
                           fg: theme.lineNumberInk.cgColor, bg: bgColor)
            }

            let rowStr = page.rowString(bufferRow)
            let rowX = viewLayout.textX0
            drawString(ctx: ctx, font: font, string: rowStr, x: rowX, y: rowY,
                       fg: fgColor, bg: bgColor)
        }
    }

    private func typewriterBufferRow(for screenRow: Int, cursorY: Int, viewRows: Int) -> Int {
        let V = viewRows
        if V <= 0 { return -1 }
        let startSy = (cursorY + 1 <= V) ? (V - (cursorY + 1)) : 0
        if screenRow < startSy { return -1 }
        let buf0 = (cursorY + 1 <= V) ? 0 : (cursorY - (V - 1))
        return buf0 + (screenRow - startSy)
    }

    private func typewriterSyForCursor(cursorY: Int, viewRows: Int) -> Int {
        let V = viewRows
        if V <= 0 { return 0 }
        let startSy = (cursorY + 1 <= V) ? (V - (cursorY + 1)) : 0
        let buf0 = (cursorY + 1 <= V) ? 0 : (cursorY - (V - 1))
        return startSy + (cursorY - buf0)
    }

    private func drawTypewriterFloatingMarginBand(ctx: CGContext, font: TypewriterFont, theme: PaperTheme) {
        let page = doc.pages[doc.curPage]
        let cellH = font.cellHeight
        let viewRows = min(viewLayout.rows, page.rows)
        guard viewRows > 0 else { return }

        var firstSy = -1
        for sy in 0..<viewRows {
            if typewriterBufferRow(for: sy, cursorY: page.cy, viewRows: viewRows) >= 0 {
                firstSy = sy
                break
            }
        }
        guard firstSy >= 0 else { return }

        let yFirst = viewLayout.textY0 + CGFloat(firstSy) * cellH
        let marginTopPx = viewLayout.marginTop
        let y0 = max(viewLayout.paperY, yFirst - marginTopPx)
        guard y0 > viewLayout.paperY, y0 < yFirst else { return }

        ctx.setFillColor(theme.paper.cgColor)
        ctx.fill(CGRect(x: viewLayout.paperX, y: y0, width: viewLayout.paperW, height: yFirst - y0))
    }

    private func drawString(ctx: CGContext, font: TypewriterFont, string: String,
                            x: CGFloat, y: CGFloat, fg: CGColor, bg: CGColor) {
        let ps = CTFontCopyPostScriptName(font.ctFont) as String
        let size = CTFontGetSize(font.ctFont)
        let nsFont = NSFont(name: ps, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: NSColor(cgColor: fg) ?? .textColor
        ]

        var currentX = x
        for (_, c) in string.enumerated() {
            guard c.isASCII, let ascii = c.asciiValue, ascii >= 32, ascii <= 126 else { continue }
            let str = String(c)
            let attrStr = NSAttributedString(string: str, attributes: attrs)
            attrStr.draw(at: CGPoint(x: currentX, y: y))
            currentX += font.cellWidth
        }
    }

    private func drawCursor(ctx: CGContext, font: TypewriterFont, theme: PaperTheme) {
        let mode = settings.cursorMode
        if mode == .hidden { return }
        if mode.isBlink && !cursorVisible { return }

        let page = doc.pages[doc.curPage]
        let cellW = font.cellWidth
        let cellH = font.cellHeight
        let cursorScreenRow: Int

        if typewriterView {
            let viewRows = min(viewLayout.rows, page.rows)
            var sy = typewriterSyForCursor(cursorY: page.cy, viewRows: viewRows)
            if sy < 0 { sy = 0 }
            if sy >= viewRows { sy = viewRows - 1 }
            cursorScreenRow = sy
        } else {
            cursorScreenRow = page.cy
        }

        let screenCol = page.cx
        let curX = viewLayout.textX0 + CGFloat(screenCol) * cellW
        let curY = viewLayout.textY0 + CGFloat(cursorScreenRow) * cellH

        let insertCursor = insertMode
        let isBlock = mode.isBlock

        if isBlock {
            ctx.setFillColor(theme.ink.cgColor)
            if insertCursor {
                ctx.fill(CGRect(x: curX, y: curY, width: 2, height: cellH))
            } else {
                ctx.fill(CGRect(x: curX, y: curY, width: cellW, height: cellH))
            }
        } else {
            ctx.setFillColor(theme.rule.cgColor)
            ctx.fill(CGRect(x: curX, y: curY, width: 2, height: cellH))
        }
    }

    private func drawTypewriterRule(ctx: CGContext, font: TypewriterFont) {
        guard typewriterView else { return }
        let theme = settings.theme
        let cellH = font.cellHeight
        let page = doc.pages[doc.curPage]
        let viewRows = min(viewLayout.rows, page.rows)
        var sy = typewriterSyForCursor(cursorY: page.cy, viewRows: viewRows)
        if sy < 0 { sy = 0 }
        if sy >= viewRows { sy = viewRows - 1 }
        let cursorScreenRow = sy
        let ruleY = viewLayout.textY0 + CGFloat(cursorScreenRow) * cellH + cellH
        ctx.setStrokeColor(theme.rule.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: viewLayout.textX0, y: ruleY))
        ctx.addLine(to: CGPoint(x: viewLayout.textX0 + CGFloat(viewLayout.cols) * font.cellWidth, y: ruleY))
        ctx.strokePath()
    }

    private func drawPageFooter(ctx: CGContext, font: TypewriterFont, theme: PaperTheme) {
        let text = "Page \(doc.curPage + 1) of \(doc.pages.count)"
        let footerY = viewLayout.paperY + viewLayout.paperH + 4
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: theme.lineNumberInk
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let footerX = viewLayout.paperX + (viewLayout.paperW - size.width) / 2
        str.draw(at: CGPoint(x: footerX, y: footerY))
    }
}

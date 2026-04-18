import UIKit

class CanvasView: UIView {
    private let settings = SettingsStore.shared
    private let fontRegistry = FontRegistry.shared
    private let soundManager = SoundManager.shared

    var doc = TwDoc(cols: 58, rows: 24)
    var onTextChange: (() -> Void)?
    var onDocInfoUpdate: ((Int, Int) -> Void)?

    private var displayLinkProxy: DisplayLinkProxy?
    private var cursorVisible = true
    private var lastBlinkTime: CFTimeInterval = 0
    private let blinkInterval: CFTimeInterval = 0.5

    private var scrollViewOffset: CGPoint = .zero
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

    private(set) var layout = ViewLayout()

    override init(frame: CGRect) {
        super.init(frame: frame)
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && displayLinkProxy == nil {
            displayLinkProxy = DisplayLinkProxy(target: self)
            displayLinkProxy?.link.add(to: .main, forMode: .common)
        }
    }

    override func removeFromSuperview() {
        displayLinkProxy?.link.invalidate()
        displayLinkProxy = nil
        super.removeFromSuperview()
    }

    @objc func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let mode = settings.cursorMode
        if mode.isBlink {
            if now - lastBlinkTime > blinkInterval {
                cursorVisible.toggle()
                lastBlinkTime = now
                setNeedsDisplay()
            }
        } else {
            if !cursorVisible {
                cursorVisible = true
                setNeedsDisplay()
            }
        }
    }

    func resetCursorBlink() {
        cursorVisible = true
        lastBlinkTime = CACurrentMediaTime()
        setNeedsDisplay()
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
        setNeedsDisplay()
    }

    func recalcLayout() {
        let twFont = fontRegistry.font(at: fontIndex)
        let cellW = twFont.cellWidth
        let cellH = twFont.cellHeight

        let boundsW = bounds.width
        let boundsH = bounds.height
        guard boundsW > 0, boundsH > 0 else { return }

        let margin: CGFloat = pageMargins ? 96 : 0
        let gutter: CGFloat
        switch gutterMode {
        case .off: gutter = 0
        case .ascending, .descending: gutter = cellW * 5
        }

        let availW = boundsW - margin * 2 - gutter
        let availH = boundsH - (pageMargins ? 20 : 0) * 2

        let targetCols: Int
        if pageMargins {
            targetCols = min(colsMargined, Int(availW / cellW))
        } else {
            targetCols = min(80, Int(availW / cellW))
        }
        let targetRows = max(1, Int(availH / cellH))

        let paperW = CGFloat(targetCols) * cellW + gutter
        let paperH = CGFloat(targetRows) * cellH
        let paperX = (boundsW - paperW) / 2
        let paperY = pageMargins ? max(20, (boundsH - paperH) / 2) : 0

        layout = ViewLayout(
            marginLeft: margin,
            marginRight: margin,
            marginTop: pageMargins ? 20 : 0,
            marginBottom: pageMargins ? 20 : 0,
            gutterWidth: gutter,
            paperX: paperX,
            paperY: paperY,
            paperW: paperW,
            paperH: paperH,
            textX0: paperX + gutter,
            textY0: paperY,
            cols: targetCols,
            rows: targetRows
        )

        if doc.cols != targetCols || doc.rows != targetRows {
            doc.resize(cols: targetCols, rows: targetRows)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        recalcLayout()
    }

    override var canBecomeFirstResponder: Bool { true }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key else { return }
        handleKey(key)
    }

    private func handleKey(_ key: UIKey) {
        let chars = key.characters
        let modifiers = key.modifierFlags

        if modifiers.contains(.control) {
            handleCtrlKey(chars: chars)
            return
        }

        if modifiers.contains(.command) {
            handleCmdKey(chars: chars)
            return
        }

switch key.keyCode {
        case .keyboardUpArrow:    doc.moveUp(); resetCursorBlink(); setNeedsDisplay()
        case .keyboardDownArrow:  doc.moveDown(); resetCursorBlink(); setNeedsDisplay()
        case .keyboardLeftArrow:  doc.moveLeft(); resetCursorBlink(); setNeedsDisplay()
        case .keyboardRightArrow: doc.moveRight(); resetCursorBlink(); setNeedsDisplay()
        case .keyboardHome:       doc.moveHome(); resetCursorBlink(); setNeedsDisplay()
        case .keyboardEnd:        doc.moveEnd(); resetCursorBlink(); setNeedsDisplay()
        case .keyboardPageUp:     doc.pageUp(); resetCursorBlink(); setNeedsDisplay()
        case .keyboardPageDown:   doc.pageDown(); resetCursorBlink(); setNeedsDisplay()
        case .keyboardDeleteForward: handleDelete()
        case let code where code.rawValue == 0x2A: handleBackspace()
        case .keyboardReturn: handleEnter()
        case .keyboardInsert:     toggleInsertMode()
        default:
            if let c = chars.first {
                if c == "\n" || c == "\r" {
                    handleEnter()
                } else if c.isASCII, let ascii = c.asciiValue, ascii >= 32, ascii < 127 {
                    typeCharacter(c)
                }
            }
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
        setNeedsDisplay()
    }

    private func handleEnter() {
        soundManager.playCarriage(for: fontIndex)
        doc.newline()
        resetCursorBlink()
        onTextChange?()
        setNeedsDisplay()
    }

    private func handleBackspace() {
        doc.backspace()
        resetCursorBlink()
        onTextChange?()
        setNeedsDisplay()
    }

    private func handleDelete() {
        doc.delete()
        resetCursorBlink()
        onTextChange?()
        setNeedsDisplay()
    }

    private func toggleInsertMode() {
        insertMode.toggle()
        settings.insertMode = insertMode
        resetCursorBlink()
        setNeedsDisplay()
    }

    private func handleCtrlKey(chars: String) {
        switch chars {
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

    func handleBackspaceFromKeyboard() {
        handleBackspace()
    }

    func handleReturnFromKeyboard() {
        handleEnter()
    }

    func handleDeleteFromKeyboard() {
        handleDelete()
    }

    private func tabInsert() {
        for _ in 0..<4 { doc.putc(" ") }
        resetCursorBlink()
        onTextChange?()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let theme = settings.theme
        let twFont = fontRegistry.font(at: fontIndex)

        if pageMargins {
            ctx.setFillColor(theme.surround.cgColor)
            ctx.fill(bounds)

            let paperRect = CGRect(x: layout.paperX, y: layout.paperY,
                                   width: layout.paperW, height: layout.paperH)
            ctx.setFillColor(theme.paper.cgColor)
            ctx.fill(paperRect)
        } else {
            ctx.setFillColor(theme.paper.cgColor)
            ctx.fill(bounds)
        }

        if typewriterView {
            let cursorScreenY: CGFloat
            if pageMargins {
                cursorScreenY = layout.paperY + CGFloat(doc.pages[doc.curPage].cy) * twFont.cellHeight
            } else {
                cursorScreenY = layout.textY0 + CGFloat(doc.pages[doc.curPage].cy) * twFont.cellHeight
            }
            ctx.setFillColor(theme.surround.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: bounds.width, height: cursorScreenY))
        }

        drawCells(ctx: ctx, font: twFont, theme: theme)
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

        for row in 0..<min(page.rows, layout.rows) {
            let bufferRow: Int
            if typewriterView {
                bufferRow = typewriterBufferRow(for: row)
            } else {
                bufferRow = row
            }
            guard bufferRow >= 0, bufferRow < page.rows else { continue }

            if gutterMode != .off {
                let lineNum: Int
                switch gutterMode {
                case .ascending: lineNum = bufferRow + 1
                case .descending: lineNum = page.rows - bufferRow
                case .off: lineNum = 0
                }
                let numStr = String(format: "%5d", lineNum)
                let gutterX = layout.textX0 - cellW * 5
                let gutterY = layout.textY0 + CGFloat(row) * cellH
                drawString(ctx: ctx, font: font, string: numStr, x: gutterX, y: gutterY,
                           fg: theme.lineNumberInk.cgColor, bg: bgColor)
            }

            let rowStr = page.rowString(bufferRow)
            let rowX = layout.textX0
            let rowY = layout.textY0 + CGFloat(row) * cellH
            drawString(ctx: ctx, font: font, string: rowStr, x: rowX, y: rowY,
                       fg: fgColor, bg: bgColor)
        }
    }

    private func typewriterBufferRow(for screenRow: Int) -> Int {
        let page = doc.pages[doc.curPage]
        let cursorY = page.cy
        let viewRows = min(layout.rows, page.rows)
        let offset = cursorY - (viewRows - 1)
        let bufRow = offset + screenRow
        return bufRow
    }

    private func drawString(ctx: CGContext, font: TypewriterFont, string: String,
                            x: CGFloat, y: CGFloat, fg: CGColor, bg: CGColor) {
        let uiFont = UIFont(name: CTFontCopyPostScriptName(font.ctFont) as String, size: CTFontGetSize(font.ctFont)) ?? UIFont.systemFont(ofSize: CTFontGetSize(font.ctFont))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .foregroundColor: UIColor(cgColor: fg)
        ]

        var currentX = x
        for (_, c) in string.enumerated() {
            guard c.isASCII, let ascii = c.asciiValue, ascii >= 32, ascii <= 126 else { continue }
            let str = String(c)
            let baselineY = y + font.ascent
            let attrStr = NSAttributedString(string: str, attributes: attrs)
            attrStr.draw(at: CGPoint(x: currentX, y: baselineY))
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
            let viewRows = min(layout.rows, page.rows)
            cursorScreenRow = viewRows - 1
        } else {
            cursorScreenRow = page.cy
        }

        let screenCol: Int
        if typewriterView {
            screenCol = page.cx
        } else {
            screenCol = page.cx
        }

        let curX = layout.textX0 + CGFloat(screenCol) * cellW
        let curY = layout.textY0 + CGFloat(cursorScreenRow) * cellH

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

        let cursorScreenRow: Int
        if typewriterView {
            let viewRows = min(layout.rows, page.rows)
            cursorScreenRow = viewRows - 1
        } else {
            cursorScreenRow = page.cy
        }

        let ruleY = layout.textY0 + CGFloat(cursorScreenRow) * cellH + cellH
        ctx.setStrokeColor(theme.rule.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: layout.textX0, y: ruleY))
        ctx.addLine(to: CGPoint(x: layout.textX0 + CGFloat(layout.cols) * font.cellWidth, y: ruleY))
        ctx.strokePath()
    }

    private func drawPageFooter(ctx: CGContext, font: TypewriterFont, theme: PaperTheme) {
        let text = "Page \(doc.curPage + 1) of \(doc.pages.count)"
        let footerY = layout.paperY + layout.paperH + 4
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: theme.lineNumberInk
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let footerX = layout.paperX + (layout.paperW - size.width) / 2
        str.draw(at: CGPoint(x: footerX, y: footerY))
    }

    func scrollToCursor() {
        if typewriterView { return }
    }
}

class DisplayLinkProxy: NSObject {
    weak var target: CanvasView?
    var link: CADisplayLink

    init(target: CanvasView) {
        self.target = target
        self.link = CADisplayLink(target: target, selector: #selector(CanvasView.tick(_:)))
        super.init()
    }
}


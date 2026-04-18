// CanvasView.swift
//
// The core renderer for Typewrite for iPad.
//
// This is a game-style text renderer — no UITextView. Characters are drawn
// into a fixed-width grid using Core Graphics/Core Text, exactly like the
// X11 original renders pixels via XPutImage. Hardware keyboard input comes
// through pressesBegan, software keyboard through UIKeyInput conformance.
//
// Rendering pipeline (called every frame via CADisplayLink):
//   1. Fill background (paper or surround color based on margins mode)
//   2. If typewriter view: blank everything above cursor row
//   3. drawCells() — iterate grid rows, blit each character via NSAttributedString
//   4. drawCursor() — draw block or bar cursor at current position
//   5. drawTypewriterRule() — red horizontal line below current row
//   6. drawPageFooter() — "Page N of M" below the paper area
//
// The document model (TwDoc/TwCore) is a multi-page character grid that
// mirrors the X11 tw_core.c / tw_doc.c architecture. See DocumentModel.swift.
//
// Key X11 → iOS translation:
//   XPutImage pixel buffer   → UIView.draw() with Core Graphics
//   XLookupKeysym            → pressesBegan(_:with:) + UIKeyInput
//   tw_bitmapfont glyph blit → Core Text NSAttributedString.draw()
//   mono_ms() cursor timer   → CADisplayLink (via DisplayLinkProxy)
//   typewriter_buf_row_for_sy → typewriterBufferRow(for:)
//
// See AGENTS.md for the full translation map.

import UIKit

class CanvasView: UIView {

    // MARK: - Dependencies

    private let settings = SettingsStore.shared
    private let fontRegistry = FontRegistry.shared
    private let soundManager = SoundManager.shared

    // MARK: - Document

    /// The multi-page character grid model. Mutated directly by input handlers.
    /// EditorView reads this via canvasState.objectWillChange for autosave.
    var doc = TwDoc(cols: 58, rows: 24)

    /// Called after every character insertion, deletion, or cursor movement
    /// to trigger autosave debounce in EditorView.
    var onTextChange: (() -> Void)?

    /// Called when page count or cursor page changes (unused currently).
    var onDocInfoUpdate: ((Int, Int) -> Void)?

    // MARK: - Cursor blink

    /// Weak-reference proxy to avoid CADisplayLink retain cycle.
    /// CADisplayLink retains its target, so we indirect through this NSObject.
    private var displayLinkProxy: DisplayLinkProxy?
    private var cursorVisible = true
    private var lastBlinkTime: CFTimeInterval = 0
    private let blinkInterval: CFTimeInterval = 0.5

    // MARK: - Settings cache (synced from SettingsStore on each update)

    private var scrollViewOffset: CGPoint = .zero
    private var pageMargins: Bool = true
    private var colsMargined: Int = 58
    private var typewriterView: Bool = true
    private var gutterMode: GutterMode = .off
    private var insertMode: Bool = false
    private var fontIndex: Int = 2

    // MARK: - Layout

    /// Computed layout metrics for the current frame. Recalculated on
    /// every layoutSubviews and when settings change.
    struct ViewLayout {
        var marginLeft: CGFloat = 0
        var marginRight: CGFloat = 0
        var marginTop: CGFloat = 0
        var marginBottom: CGFloat = 0
        var gutterWidth: CGFloat = 0
        var paperX: CGFloat = 0    // left edge of paper rect
        var paperY: CGFloat = 0    // top edge of paper rect
        var paperW: CGFloat = 0    // width of paper rect
        var paperH: CGFloat = 0    // height of paper rect
        var textX0: CGFloat = 0    // left edge of text area (paperX + gutter)
        var textY0: CGFloat = 0    // top edge of text area
        var cols: Int = 58          // number of character columns
        var rows: Int = 24         // number of character rows
    }

    private(set) var layout = ViewLayout()

    // MARK: - Initialization

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

    // MARK: - DisplayLink lifecycle

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

    /// Called by CADisplayLink every frame. Only toggles cursor visibility
    /// for blink modes; non-blink modes force cursor always-visible.
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

    /// Resets cursor to visible and restarts blink timer. Called on every
    /// key press so the cursor stays solid during typing.
    func resetCursorBlink() {
        cursorVisible = true
        lastBlinkTime = CACurrentMediaTime()
        setNeedsDisplay()
    }

    /// Syncs all settings from SettingsStore into local cache, then
    /// recalculates layout and redraws. Called by CanvasRepresentable
    /// on every SwiftUI state change.
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

    // MARK: - Layout calculation

    /// Calculates the ViewLayout struct based on current bounds, font metrics,
    /// and settings. If the document grid dimensions changed, resizes TwDoc.
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

        // Column count: constrained by settings when margins are on
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

        // Resize the document grid if column/row count changed (e.g. rotation)
        if doc.cols != targetCols || doc.rows != targetRows {
            doc.resize(cols: targetCols, rows: targetRows)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        recalcLayout()
    }

    // MARK: - Keyboard input (hardware keyboard via pressesBegan, software via UIKeyInput)

    override var canBecomeFirstResponder: Bool { true }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    // UIKeyInput conformance — enables iOS system keyboard when no
    // hardware keyboard is attached. iOS automatically shows/hides
    // the software keyboard based on hardware KB presence.
    var hasText: Bool { true }

    func insertText(_ text: String) {
        for c in text {
            insertCharacter(c)
        }
    }

    func deleteBackward() {
        handleBackspace()
    }

    /// Hardware keyboard input. Maps UIKey.keyCode to document operations.
    /// Arrows → cursor movement, Delete/Backspace → deletion, Enter → newline.
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
        case let code where code.rawValue == 0x2A: handleBackspace()  // USB HID backspace
        case .keyboardReturn: handleEnter()
        case .keyboardInsert:     toggleInsertMode()
        default:
            // Catch newline characters that arrive without .keyboardReturn keyCode
            if let c = chars.first {
                if c == "\n" || c == "\r" {
                    handleEnter()
                } else if c.isASCII, let ascii = c.asciiValue, ascii >= 32, ascii < 127 {
                    typeCharacter(c)
                }
            }
        }
    }

    // MARK: - Character input handlers (both hardware and software keyboard)

    /// Routes a printable character to the correct handler based on type.
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

    /// Types a single character with font-appropriate sound effect.
    /// For typewriter fonts (indices 2-3), plays a margin bell when
    /// approaching the right edge, just like a real typewriter.
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

    /// Backspace: plays the key sound reversed (via SoundManager.playDelete)
    private func handleBackspace() {
        soundManager.playDelete(for: fontIndex)
        doc.backspace()
        resetCursorBlink()
        onTextChange?()
        setNeedsDisplay()
    }

    /// Forward delete: also plays reversed key sound
    private func handleDelete() {
        soundManager.playDelete(for: fontIndex)
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

    /// Public entry point for soft keyboard characters (UIKeyInput.insertText)
    /// and for any external input source.
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

    // Passthrough methods for soft keyboard delegate
    func handleBackspaceFromKeyboard() { handleBackspace() }
    func handleReturnFromKeyboard() { handleEnter() }
    func handleDeleteFromKeyboard() { handleDelete() }

    /// Inserts 4 spaces with a single key sound (not 4 separate sounds).
    private func tabInsert() {
        for _ in 0..<4 { doc.putc(" ") }
        resetCursorBlink()
        onTextChange?()
        setNeedsDisplay()
    }

    // MARK: - Rendering

    /// Main draw cycle. Called by iOS whenever setNeedsDisplay() fires.
    /// Renders the paper/ink background, then layers text, cursor, and rule.
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let theme = settings.theme
        let twFont = fontRegistry.font(at: fontIndex)

        // Background: with margins, draw surround then paper rect.
        // Without margins, paper fills entire view.
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

        // Typewriter view: blank everything above the cursor line,
        // so text appears to scroll up from below (like a real typewriter).
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

    /// Draws all visible rows of the character grid, including optional
    /// line number gutter. In typewriter mode, rows above the cursor are
    /// scrolled off-screen via typewriterBufferRow(for:).
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

            // Line number gutter (5 characters wide, right-aligned)
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

            // Text row
            let rowStr = page.rowString(bufferRow)
            let rowX = layout.textX0
            let rowY = layout.textY0 + CGFloat(row) * cellH
            drawString(ctx: ctx, font: font, string: rowStr, x: rowX, y: rowY,
                       fg: fgColor, bg: bgColor)
        }
    }

    /// In typewriter view mode, the cursor stays on the last visible row.
    /// This function maps screen row → document row by computing the offset
    /// so that the cursor line is always at the bottom of the screen.
    /// Matches the X11 function typewriter_buf_row_for_sy().
    private func typewriterBufferRow(for screenRow: Int) -> Int {
        let page = doc.pages[doc.curPage]
        let cursorY = page.cy
        let viewRows = min(layout.rows, page.rows)
        let offset = cursorY - (viewRows - 1)
        return offset + screenRow
    }

    /// Draws a string of printable ASCII characters at monospaced grid positions.
    /// Each character is drawn at (x + i*cellWidth, y + ascent) to align
    /// the font baseline correctly within each grid cell.
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

    /// Draws the cursor at the current cursor position. In typewriter view,
    /// the cursor is always on the bottom row. Supports 5 cursor modes:
    /// bar, blink-bar, block, blink-block, hidden.
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

        let screenCol = page.cx

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

    /// Draws the red typewriter rule line below the cursor row.
    /// This is the visual cue that the "paper roller" is at this line.
    private func drawTypewriterRule(ctx: CGContext, font: TypewriterFont) {
        guard typewriterView else { return }
        let theme = settings.theme
        let cellH = font.cellHeight
        let page = doc.pages[doc.curPage]

        let viewRows = min(layout.rows, page.rows)
        let cursorScreenRow = viewRows - 1

        let ruleY = layout.textY0 + CGFloat(cursorScreenRow) * cellH + cellH
        ctx.setStrokeColor(theme.rule.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: layout.textX0, y: ruleY))
        ctx.addLine(to: CGPoint(x: layout.textX0 + CGFloat(layout.cols) * font.cellWidth, y: ruleY))
        ctx.strokePath()
    }

    /// Draws "Page N of M" footer below the paper area (margins mode only).
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

    /// Placeholder for non-typewriter scroll-to-cursor implementation.
    func scrollToCursor() {
        if typewriterView { return }
    }
}

/// Breaks the CADisplayLink retain cycle. CADisplayLink retains its target,
/// and if the target is CanvasView (which also holds the link via
/// displayLinkProxy), we'd have a cycle. DisplayLinkProxy holds a weak
/// reference to CanvasView, breaking the cycle.
class DisplayLinkProxy: NSObject {
    weak var target: CanvasView?
    var link: CADisplayLink

    init(target: CanvasView) {
        self.target = target
        self.link = CADisplayLink(target: target, selector: #selector(CanvasView.tick(_:)))
        super.init()
    }
}
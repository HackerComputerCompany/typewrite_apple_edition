import SwiftUI

struct EditorView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showHelp = false
    @State private var toastText: String?
    @State private var toastOpacity: Double = 0
    @State private var toastTimer: Timer?
    @State private var showSoftKeyboard = true
    @State private var canvasView = CanvasView()
    @State private var doc = TwDoc()
    @State private var fileName = "Typewriter.txt"
    @State private var showDocumentPicker = false
    @State private var showExportPicker = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack {
                    CanvasRepresentable(canvasView: canvasView, doc: $doc, settings: settings, onTextChange: {
                        scheduleAutosave()
                    })

                    toastOverlay
                    helpOverlay
                }
                .frame(maxHeight: .infinity)

                if showSoftKeyboard {
                    SoftKeyboardRepresentable(theme: settings.theme, canvasView: canvasView)
                        .frame(height: keyboardHeight)
                }
            }
        }
        .background(Color(settings.theme.surround))
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                bottomToolbar
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                topToolbar
            }
        }
        .onAppear {
            SoundManager.shared.preload()
        }
    }

    private var keyboardHeight: CGFloat {
        SoftKeyboardView.estimatedHeight
    }

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            Button { cycleFont() } label: {
                Image(systemName: "textformat")
            }
            Button { cycleTheme() } label: {
                Image(systemName: "circle.lefthalf.filled")
            }
            Button { cycleCursor() } label: {
                Image(systemName: "cursor.ibeam")
            }
            Button { toggleTypewriter() } label: {
                Image(systemName: settings.typewriterView ? "arrow.down.to.line" : "arrow.up.to.line")
            }
            Button { toggleMargins() } label: {
                Image(systemName: settings.pageMargins ? "doc.richtext" : "doc.plaintext")
            }
            Button { toggleInsert() } label: {
                Text(settings.insertMode ? "INS" : "OVR")
                    .font(.system(.caption2, design: .monospaced))
                    .monospacedDigit()
            }
            Button { showSoftKeyboard.toggle() } label: {
                Image(systemName: showSoftKeyboard ? "keyboard" : "keyboard.badge.chevron.compact.down")
            }
            Spacer()
            Text("Page \(doc.curPage + 1)/\(doc.pages.count)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private var topToolbar: some View {
        HStack(spacing: 12) {
            Button { showHelp = true } label: {
                Image(systemName: "questionmark.circle")
            }
            Button { showDocumentPicker = true } label: {
                Image(systemName: "folder")
            }
            .fileImporter(isPresented: $showDocumentPicker, allowedContentTypes: [.plainText]) { result in
                handleOpen(result)
            }
            Button { showExportPicker = true } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .fileExporter(isPresented: $showExportPicker, document: PlainTextDocument(text: doc.fullText()), contentType: .plainText) { _ in }
        }
    }

    private var toastOverlay: some View {
        Group {
            if let text = toastText {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .opacity(toastOpacity)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 50)
    }

    private var helpOverlay: some View {
        Group {
            if showHelp {
                HelpOverlay(settings: settings, onDismiss: {
                    showHelp = false
                }, onAction: { action in
                    handleHelpAction(action)
                })
            }
        }
    }

    private func handleHelpAction(_ action: HelpOverlay.HelpAction) {
        switch action {
        case .cycleFont: cycleFont()
        case .cycleCursor: cycleCursor()
        case .cycleTheme: cycleTheme()
        case .cycleGutter: cycleGutter()
        case .toggleMargins: toggleMargins()
        case .cycleCols: cycleCols()
        case .toggleTypewriter: toggleTypewriter()
        case .toggleWordWrap: toggleWordWrap()
        case .toggleInsert: toggleInsert()
        }
    }

    @discardableResult
    private func cycleFont() -> String {
        settings.fontIndex = (settings.fontIndex + 1) % 9
        let name = FontRegistry.shared.font(at: settings.fontIndex).displayName
        showToast("Font: \(name)")
        return name
    }

    private func cycleTheme() {
        settings.themeIndex = (settings.themeIndex + 1) % PaperTheme.allCases.count
        showToast("Theme: \(settings.theme.displayName)")
    }

    private func cycleCursor() {
        let next = (settings.cursorMode.rawValue + 1) % CursorMode.allCases.count
        settings.cursorMode = CursorMode(rawValue: next) ?? .bar
        showToast("Cursor: \(settings.cursorMode.displayName)")
    }

    private func cycleGutter() {
        let next = (settings.gutterMode.rawValue + 1) % GutterMode.allCases.count
        settings.gutterMode = GutterMode(rawValue: next) ?? .off
        showToast("Lines: \(settings.gutterMode == .off ? "Off" : settings.gutterMode == .ascending ? "Ascending" : "Descending")")
    }

    private func toggleMargins() {
        settings.pageMargins.toggle()
        showToast(settings.pageMargins ? "Margins: On" : "Margins: Off")
    }

    private func cycleCols() {
        let options = [50, 55, 58, 60, 65]
        guard let idx = options.firstIndex(of: settings.colsMargined) else { return }
        settings.colsMargined = options[(idx + 1) % options.count]
        showToast("Cols: \(settings.colsMargined)")
    }

    private func toggleTypewriter() {
        settings.typewriterView.toggle()
        showToast(settings.typewriterView ? "Typewriter: On" : "Typewriter: Off")
    }

    private func toggleWordWrap() {
        settings.wordWrap.toggle()
        showToast(settings.wordWrap ? "Word Wrap: On" : "Word Wrap: Off")
    }

    private func toggleInsert() {
        settings.insertMode.toggle()
        showToast(settings.insertMode ? "Insert Mode" : "Typeover Mode")
    }

    private func showToast(_ text: String) {
        toastText = text
        withAnimation { toastOpacity = 1 }
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            withAnimation { toastOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                toastText = nil
            }
        }
    }

    private func scheduleAutosave() {}

    private func handleOpen(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                doc.load(text)
                fileName = url.lastPathComponent
            }
        case .failure: break
        }
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    var canvasView: CanvasView
    @Binding var doc: TwDoc
    @ObservedObject var settings: SettingsStore
    var onTextChange: (() -> Void)?

    func makeUIView(context: Context) -> CanvasView {
        canvasView.doc = doc
        canvasView.onTextChange = onTextChange
        canvasView.updateFromSettings()
        canvasView.becomeFirstResponder()
        return canvasView
    }

    func updateUIView(_ uiView: CanvasView, context: Context) {
        uiView.doc = doc
        uiView.onTextChange = onTextChange
        uiView.updateFromSettings()
        uiView.setNeedsDisplay()
        uiView.becomeFirstResponder()
    }
}

struct SoftKeyboardRepresentable: UIViewRepresentable {
    var theme: PaperTheme
    var canvasView: CanvasView

    func makeUIView(context: Context) -> SoftKeyboardView {
        let kb = SoftKeyboardView(initialTheme: theme)
        kb.delegate = context.coordinator
        return kb
    }

    func updateUIView(_ uiView: SoftKeyboardView, context: Context) {
        uiView.theme = theme
        uiView.setNeedsDisplay()
        context.coordinator.canvasView = canvasView
    }

    func makeCoordinator() -> KeyboardCoordinator {
        KeyboardCoordinator(canvasView: canvasView)
    }
}

class KeyboardCoordinator: NSObject, SoftKeyboardDelegate {
    var canvasView: CanvasView

    init(canvasView: CanvasView) {
        self.canvasView = canvasView
    }

    func softKeyboard(_ keyboard: SoftKeyboardView, didPress character: Character) {
        canvasView.insertCharacter(character)
    }

    func softKeyboardDidPressBackspace(_ keyboard: SoftKeyboardView) {
        canvasView.handleBackspaceFromKeyboard()
    }

    func softKeyboardDidPressReturn(_ keyboard: SoftKeyboardView) {
        canvasView.handleReturnFromKeyboard()
    }

    func softKeyboardDidPressTab(_ keyboard: SoftKeyboardView) {
        for _ in 0..<4 { canvasView.insertCharacter(" ") }
    }

    func softKeyboardDidPressDelete(_ keyboard: SoftKeyboardView) {
        canvasView.handleDeleteFromKeyboard()
    }

    func softKeyboardDidToggleShift(_ keyboard: SoftKeyboardView, shifted: Bool) {
    }
}
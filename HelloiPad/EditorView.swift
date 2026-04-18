import SwiftUI

class CanvasViewState: ObservableObject {
    let canvas = CanvasView()
}

struct EditorView: View {
    var initialText: String = ""
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showHelp = false
    @State private var toastText: String?
    @State private var toastOpacity: Double = 0
    @State private var toastTimer: Timer?
    @StateObject private var canvasState = CanvasViewState()
    @State private var fileName = "Typewriter.txt"
    @State private var showDocumentPicker = false
    @State private var showExportPicker = false
    @State private var toolbarVisible = true
    @FocusState private var canvasFocused: Bool

    private var canvas: CanvasView { canvasState.canvas }

    var body: some View {
        ZStack {
            canvasArea
                .ignoresSafeArea()

            VStack {
                Spacer()
                if toolbarVisible {
                    toolbarBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            toastOverlay
            helpOverlay
        }
        .background(Color(settings.theme.surround))
        .statusBarHidden(!toolbarVisible)
        .onAppear {
            if !initialText.isEmpty {
                canvas.doc.load(initialText)
            }
            SoundManager.shared.preload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                canvasFocused = true
            }
        }
    }

    private var canvasArea: some View {
        CanvasRepresentable(canvasView: canvas, settings: settings, onTextChange: {
            canvasState.objectWillChange.send()
        })
        .focused($canvasFocused)
    }

    private var toolbarBar: some View {
        HStack(spacing: 16) {
            Button { showHelp = true } label: {
                Image(systemName: "questionmark.circle")
            }
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
            Spacer()
            Button { showDocumentPicker = true } label: {
                Image(systemName: "folder")
            }
            .fileImporter(isPresented: $showDocumentPicker, allowedContentTypes: [.plainText]) { result in
                handleOpen(result)
            }
            Button { showExportPicker = true } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .fileExporter(isPresented: $showExportPicker, document: PlainTextDocument(text: canvas.doc.fullText()), contentType: .plainText) { _ in }
            Button { withAnimation { toolbarVisible.toggle() } } label: {
                Image(systemName: "chevron.down")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
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

    private func handleOpen(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                canvas.doc.load(text)
                fileName = url.lastPathComponent
            }
        case .failure: break
        }
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    var canvasView: CanvasView
    @ObservedObject var settings: SettingsStore
    var onTextChange: (() -> Void)?

    func makeUIView(context: Context) -> CanvasView {
        canvasView.onTextChange = onTextChange
        canvasView.updateFromSettings()
        canvasView.becomeFirstResponder()
        return canvasView
    }

    func updateUIView(_ uiView: CanvasView, context: Context) {
        uiView.onTextChange = onTextChange
        uiView.updateFromSettings()
        uiView.setNeedsDisplay()
    }
}
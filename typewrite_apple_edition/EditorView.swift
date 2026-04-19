import SwiftUI
import Combine

#if os(macOS)
import AppKit

extension Notification.Name {
    static let editorMenuAction = Notification.Name("com.hackercomputercompany.typewrite.editorMenuAction")
}

/// Dispatched from the macOS menu bar; handled only by the key editor window (see `MacKeyWindowBridge`).
enum EditorMenuAction: String {
    case showHelp
    case cycleFont
    case cycleTheme
    case cycleCursor
    case toggleTypewriter
    case toggleMargins
    case toggleInsert
    case openDocument
    case exportDocument
    case cycleGutter
    case cycleCols
    case toggleWordWrap
    case toggleSounds
    case cycleStatusPulse
}
#endif

#if os(iOS)
final class CanvasViewState: ObservableObject {
    let canvas = CanvasView()
}
#elseif os(macOS)
final class CanvasViewState: ObservableObject {
    let canvas = CanvasNSView()
}
#endif

private let statusPulseTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

struct EditorView: View {
    @ObservedObject var document: PlainTextDocument
    @ObservedObject private var settings = SettingsStore.shared
    @State private var showHelp = false
    @State private var toastText: String?
    @State private var toastOpacity: Double = 0
    @State private var toastTimer: Timer?
    @StateObject private var canvasState = CanvasViewState()
    @StateObject private var sessionTracker = WritingSessionTracker()
    @State private var nextStatusPulseAt: Date = .distantFuture
    @State private var showDocumentPicker = false
    @State private var showExportPicker = false
    @State private var toolbarExpanded = true
    @State private var autosaveTimer: Timer?
    @FocusState private var canvasFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @State private var windowIsKey = false
    #endif

    #if os(iOS)
    private var canvas: CanvasView { canvasState.canvas }
    #elseif os(macOS)
    private var canvas: CanvasNSView { canvasState.canvas }
    #endif

    var body: some View {
        ZStack {
            canvasArea
                .ignoresSafeArea()

            #if os(macOS)
            if settings.macShowFloatingToolbar {
                floatingToolbar
            }
            #else
            floatingToolbar
            #endif

            toastOverlay
            helpOverlay
        }
        .background(settings.theme.surroundSwiftUI)
        #if os(macOS)
        .overlay(alignment: .topLeading) {
            MacKeyWindowBridge(isKeyWindow: $windowIsKey)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorMenuAction)) { note in
            guard windowIsKey else { return }
            guard let raw = note.userInfo?["action"] as? String,
                  let action = EditorMenuAction(rawValue: raw) else { return }
            handleEditorMenuAction(action)
        }
        #endif
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                saveNow()
            }
        }
        .onAppear {
            if !document.text.isEmpty {
                canvas.doc.load(document.text)
            }
            SoundManager.shared.preload()
            alignStatusPulseSchedule()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                canvasFocused = true
            }
        }
        .onChange(of: settings.statusPulseIndex) { _, _ in
            alignStatusPulseSchedule()
        }
        .onReceive(statusPulseTicker) { _ in
            tickStatusPulseIfDue()
        }
        .fileImporter(isPresented: $showDocumentPicker, allowedContentTypes: [.plainText]) { result in
            handleOpen(result)
        }
        .fileExporter(isPresented: $showExportPicker, document: document, contentType: .plainText) { _ in }
    }

    private var canvasArea: some View {
        CanvasRepresentable(
            canvasView: canvas,
            settings: settings,
            onTextChange: {
                canvasState.objectWillChange.send()
                scheduleAutosave()
            },
            onTypingSessionInput: { sessionTracker.note($0) },
            onStatusPulseShortcut: { cycleStatusPulse() },
            onToggleSoundsShortcut: { toggleSounds() }
        )
        .focused($canvasFocused)
    }

    /// Sits in the outer margin (trailing), vertical, glass + shadow so it reads as floating over the surround.
    private var floatingToolbar: some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer(minLength: 0)
            toolbarStrip
                .padding(.trailing, 10)
        }
        .padding(.vertical, 48)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var toolbarStrip: some View {
        if toolbarExpanded {
            VStack(spacing: 12) {
                Button { showHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                }
                Button { cycleFont() } label: {
                    Image(systemName: "textformat")
                }
                Button { cycleTheme() } label: {
                    Image(systemName: "circle.lefthalf.filled")
                }
                Button { toggleSounds() } label: {
                    Image(systemName: settings.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                }
                .accessibilityLabel(settings.soundEnabled ? "Mute sounds" : "Unmute sounds")
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
                        .frame(minWidth: 28)
                }
                Button { showDocumentPicker = true } label: {
                    Image(systemName: "folder")
                }
                Button { showExportPicker = true } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { toolbarExpanded = false } } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .accessibilityLabel("Collapse toolbar")
            }
            .font(.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 14, x: -4, y: 6)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            ))
        } else {
            Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { toolbarExpanded = true } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 12, x: -3, y: 5)
            .accessibilityLabel("Expand toolbar")
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            ))
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

    // MARK: - Autosave

    private func scheduleAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            saveNow()
        }
    }

    private func saveNow() {
        document.text = canvas.doc.fullText()
    }

    // MARK: - Actions

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
        case .toggleSounds: toggleSounds()
        case .cycleStatusPulse: cycleStatusPulse()
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

    private func toggleSounds() {
        settings.soundEnabled.toggle()
        showToast(settings.soundEnabled ? "Sounds: On" : "Sounds: Off")
    }

    /// X11 F9: cycle 1 min … 1 hr check-in interval for gentle session toasts.
    private func cycleStatusPulse() {
        settings.statusPulseIndex = (settings.statusPulseIndex + 1) % SettingsStore.statusPulseCount
        showToast("Check-in: every \(settings.statusPulseIntervalLabel)", duration: 2.5)
        alignStatusPulseSchedule()
    }

    private func alignStatusPulseSchedule() {
        nextStatusPulseAt = Date().addingTimeInterval(settings.statusPulseIntervalSeconds)
    }

    private func tickStatusPulseIfDue() {
        guard scenePhase == .active else { return }
        guard Date() >= nextStatusPulseAt else { return }
        alignStatusPulseSchedule()
        let msg = sessionTracker.statusPulseMessage(for: canvas.doc)
        showToast(msg, duration: 4.0)
    }

    private func showToast(_ text: String, duration: TimeInterval = 2.0) {
        toastText = text
        withAnimation { toastOpacity = 1 }
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
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
                sessionTracker.resetSession()
                saveNow()
            }
        case .failure: break
        }
    }
}

#if os(macOS)
extension EditorView {
    fileprivate func handleEditorMenuAction(_ action: EditorMenuAction) {
        switch action {
        case .showHelp: showHelp = true
        case .cycleFont: cycleFont()
        case .cycleTheme: cycleTheme()
        case .cycleCursor: cycleCursor()
        case .toggleTypewriter: toggleTypewriter()
        case .toggleMargins: toggleMargins()
        case .toggleInsert: toggleInsert()
        case .openDocument: showDocumentPicker = true
        case .exportDocument: showExportPicker = true
        case .cycleGutter: cycleGutter()
        case .cycleCols: cycleCols()
        case .toggleWordWrap: toggleWordWrap()
        case .toggleSounds: toggleSounds()
        case .cycleStatusPulse: cycleStatusPulse()
        }
    }
}

private struct MacKeyWindowBridge: NSViewRepresentable {
    @Binding var isKeyWindow: Bool

    func makeNSView(context: Context) -> KeyWindowDetectorView {
        let v = KeyWindowDetectorView()
        v.onKeyChange = { isKeyWindow = $0 }
        return v
    }

    func updateNSView(_ nsView: KeyWindowDetectorView, context: Context) {
        nsView.onKeyChange = { isKeyWindow = $0 }
    }
}

private final class KeyWindowDetectorView: NSView {
    var onKeyChange: ((Bool) -> Void)?
    private var becomeToken: NSObjectProtocol?
    private var resignToken: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tearDownObservers()
        guard let win = window else {
            onKeyChange?(false)
            return
        }
        onKeyChange?(win.isKeyWindow)
        becomeToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            self?.onKeyChange?(true)
        }
        resignToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            self?.onKeyChange?(false)
        }
    }

    private func tearDownObservers() {
        if let t = becomeToken { NotificationCenter.default.removeObserver(t) }
        if let t = resignToken { NotificationCenter.default.removeObserver(t) }
        becomeToken = nil
        resignToken = nil
    }

    deinit {
        tearDownObservers()
    }
}
#endif

#if os(iOS)
struct CanvasRepresentable: UIViewRepresentable {
    var canvasView: CanvasView
    @ObservedObject var settings: SettingsStore
    var onTextChange: (() -> Void)?
    var onTypingSessionInput: ((TypingSessionInput) -> Void)?
    var onStatusPulseShortcut: (() -> Void)?
    var onToggleSoundsShortcut: (() -> Void)?

    func makeUIView(context: Context) -> CanvasView {
        canvasView.onTextChange = onTextChange
        canvasView.onTypingSessionInput = onTypingSessionInput
        canvasView.onStatusPulseShortcut = onStatusPulseShortcut
        canvasView.onToggleSoundsShortcut = onToggleSoundsShortcut
        canvasView.updateFromSettings()
        canvasView.claimFocus()
        return canvasView
    }

    func updateUIView(_ uiView: CanvasView, context: Context) {
        uiView.onTextChange = onTextChange
        uiView.onTypingSessionInput = onTypingSessionInput
        uiView.onStatusPulseShortcut = onStatusPulseShortcut
        uiView.onToggleSoundsShortcut = onToggleSoundsShortcut
        uiView.updateFromSettings()
        uiView.setNeedsDisplay()
    }
}
#elseif os(macOS)
struct CanvasRepresentable: NSViewRepresentable {
    var canvasView: CanvasNSView
    @ObservedObject var settings: SettingsStore
    var onTextChange: (() -> Void)?
    var onTypingSessionInput: ((TypingSessionInput) -> Void)?
    var onStatusPulseShortcut: (() -> Void)?
    var onToggleSoundsShortcut: (() -> Void)?

    func makeNSView(context: Context) -> CanvasNSView {
        canvasView.onTextChange = onTextChange
        canvasView.onTypingSessionInput = onTypingSessionInput
        canvasView.onStatusPulseShortcut = onStatusPulseShortcut
        canvasView.onToggleSoundsShortcut = onToggleSoundsShortcut
        canvasView.updateFromSettings()
        canvasView.claimFocus()
        return canvasView
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.onTextChange = onTextChange
        nsView.onTypingSessionInput = onTypingSessionInput
        nsView.onStatusPulseShortcut = onStatusPulseShortcut
        nsView.onToggleSoundsShortcut = onToggleSoundsShortcut
        nsView.updateFromSettings()
        nsView.needsDisplay = true
    }
}
#endif
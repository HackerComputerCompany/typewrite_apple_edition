import SwiftUI
import Combine
import UniformTypeIdentifiers

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
    case showWindowBackground
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
    @ObservedObject var document: TypewriteDocument
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
    /// macOS: sheet for window vibrancy + surround transparency (unused on iOS).
    @State private var showMacWindowAppearanceSheet = false
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

    private var inkToolbarColor: Color {
        switch settings.activeInk {
        case .ink: return .primary
        case .red: return .red
        case .blue: return .blue
        }
    }

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
        #if os(macOS)
        .background {
            MacEditorRootChrome(settings: settings)
                .ignoresSafeArea()
        }
        #else
        .background(settings.theme.surroundSwiftUI)
        #endif
        #if os(macOS)
        .overlay(alignment: .topLeading) {
            ZStack {
                MacKeyWindowBridge(isKeyWindow: $windowIsKey)
                MacWindowVibrancyBridge(blurPercent: settings.macChromeBlurPercent)
            }
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
        .sheet(isPresented: $showMacWindowAppearanceSheet) {
            MacWindowAppearanceSheet(settings: settings) {
                showMacWindowAppearanceSheet = false
            }
        }
        #endif
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                saveNow()
            }
        }
        .onAppear {
            applyFilePayloadToCanvas()
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
        .fileImporter(isPresented: $showDocumentPicker, allowedContentTypes: [.typewriteDocument, .plainText, .utf8PlainText]) { result in
            handleOpen(result)
        }
        .fileExporter(isPresented: $showExportPicker, document: document, contentType: .typewriteDocument) { _ in }
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
            onToggleSoundsShortcut: { toggleSounds() },
            onCycleInkShortcut: { cycleInkColor() }
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
                Button { cycleInkColor() } label: {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(inkToolbarColor)
                }
                .accessibilityLabel("Cycle ink color")
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
                #if os(macOS)
                Button { showMacWindowAppearanceSheet = true } label: {
                    Image(systemName: "rectangle.dashed")
                }
                .accessibilityLabel("Window background blur and transparency")
                #endif
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
        document.updateSnapshot(
            doc: canvas.doc,
            session: sessionTracker.sessionMetadataForArchive()
        )
    }

    private func applyFilePayloadToCanvas() {
        if document.openedAsPlainText {
            canvas.doc.load(String(decoding: document.fileData, as: UTF8.self))
        } else if let result = try? TwBinaryArchiveV1.decode(document.fileData) {
            canvas.doc = result.0
            sessionTracker.applySessionMetadata(result.1)
        }
        canvas.rebindDocumentBell()
        canvas.updateFromSettings()
        refreshCanvasAfterDocumentLoad()
    }

    /// `TwDoc.load` does not go through the keyboard path, so the UIView/AppKit view may not redraw until
    /// the next `updateUIView`/`updateNSView`. A second pass runs after any pending layout/resize.
    private func refreshCanvasAfterDocumentLoad() {
        canvas.resetCursorBlink()
        let c = canvas
        DispatchQueue.main.async { c.resetCursorBlink() }
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
        case .cycleInk: cycleInkColor()
        }
    }

    private func cycleInkColor() {
        settings.cycleInkColor()
        canvas.updateFromSettings()
        let names = ["Default", "Red", "Blue"]
        showToast("Ink: \(names[min(settings.inkColorIndex, 2)])")
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
            guard let data = try? Data(contentsOf: url) else { return }
            if data.count >= 4, String(data: data[0..<4], encoding: .ascii) == TwBinaryArchiveV1.magic,
               let decoded = try? TwBinaryArchiveV1.decode(data) {
                canvas.doc = decoded.0
                sessionTracker.applySessionMetadata(decoded.1)
            } else if let text = String(data: data, encoding: .utf8) {
                canvas.doc.load(text)
                sessionTracker.resetSession()
            }
            canvas.rebindDocumentBell()
            saveNow()
            refreshCanvasAfterDocumentLoad()
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
        case .showWindowBackground: showMacWindowAppearanceSheet = true
        }
    }
}

// MARK: - macOS window chrome (vibrancy + adjustable tint)

private struct MacEditorRootChrome: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        let theme = settings.theme
        let blur = settings.macChromeBlurPercent
        let a = settings.macSurroundTintAlpha()
        ZStack {
            if blur > 0 {
                MacChromeBackdropView(blurPercent: blur)
                Color(nsColor: theme.surround).opacity(Double(a))
            } else {
                Color(nsColor: theme.surround).opacity(Double(a))
            }
        }
    }
}

private struct MacChromeBackdropView: NSViewRepresentable {
    var blurPercent: Int

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = Self.material(for: blurPercent)
    }

    private static func material(for blurPercent: Int) -> NSVisualEffectView.Material {
        let b = min(max(blurPercent, 1), 100)
        switch b {
        case 1..<21: return .contentBackground
        case 21..<41: return .sidebar
        case 41..<61: return .underWindowBackground
        case 61..<81: return .hudWindow
        default: return .fullScreenUI
        }
    }
}

private struct MacWindowVibrancyBridge: NSViewRepresentable {
    var blurPercent: Int

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ v: NSView, context: Context) {
        guard let w = v.window else { return }
        if blurPercent > 0 {
            w.isOpaque = false
            w.backgroundColor = .clear
        } else {
            w.isOpaque = true
            w.backgroundColor = .windowBackgroundColor
        }
    }
}

private struct MacWindowAppearanceSheet: View {
    @ObservedObject var settings: SettingsStore
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Slider(value: blurBinding, in: 0...100, step: 1)
                    Text(blurCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Background blur")
                } footer: {
                    Text("0 keeps a solid window; higher values use a frosted material behind the editor.")
                }

                Section {
                    Slider(value: transparencyBinding, in: 1...100, step: 1)
                    Text("Surround tint: \(settings.macChromeTransparencyPercent)% transparent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Surround transparency")
                } footer: {
                    Text("1% is nearly opaque; 100% removes the dark surround tint so only blur (if any) shows through.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Window background")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 320)
    }

    private var blurCaption: String {
        switch settings.macChromeBlurPercent {
        case 0: return "Blur: off (solid)"
        case 1..<26: return "Blur: light"
        case 26..<51: return "Blur: medium"
        case 51..<76: return "Blur: strong"
        default: return "Blur: maximum"
        }
    }

    private var blurBinding: Binding<Double> {
        Binding(
            get: { Double(settings.macChromeBlurPercent) },
            set: { settings.macChromeBlurPercent = Int($0.rounded()) }
        )
    }

    private var transparencyBinding: Binding<Double> {
        Binding(
            get: { Double(settings.macChromeTransparencyPercent) },
            set: { settings.macChromeTransparencyPercent = Int($0.rounded()) }
        )
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
    var onCycleInkShortcut: (() -> Void)?

    func makeUIView(context: Context) -> CanvasView {
        canvasView.onTextChange = onTextChange
        canvasView.onTypingSessionInput = onTypingSessionInput
        canvasView.onStatusPulseShortcut = onStatusPulseShortcut
        canvasView.onToggleSoundsShortcut = onToggleSoundsShortcut
        canvasView.onCycleInkShortcut = onCycleInkShortcut
        canvasView.updateFromSettings()
        canvasView.claimFocus()
        return canvasView
    }

    func updateUIView(_ uiView: CanvasView, context: Context) {
        uiView.onTextChange = onTextChange
        uiView.onTypingSessionInput = onTypingSessionInput
        uiView.onStatusPulseShortcut = onStatusPulseShortcut
        uiView.onToggleSoundsShortcut = onToggleSoundsShortcut
        uiView.onCycleInkShortcut = onCycleInkShortcut
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
    var onCycleInkShortcut: (() -> Void)?

    func makeNSView(context: Context) -> CanvasNSView {
        canvasView.onTextChange = onTextChange
        canvasView.onTypingSessionInput = onTypingSessionInput
        canvasView.onStatusPulseShortcut = onStatusPulseShortcut
        canvasView.onToggleSoundsShortcut = onToggleSoundsShortcut
        canvasView.onCycleInkShortcut = onCycleInkShortcut
        canvasView.updateFromSettings()
        canvasView.claimFocus()
        return canvasView
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.onTextChange = onTextChange
        nsView.onTypingSessionInput = onTypingSessionInput
        nsView.onStatusPulseShortcut = onStatusPulseShortcut
        nsView.onToggleSoundsShortcut = onToggleSoundsShortcut
        nsView.onCycleInkShortcut = onCycleInkShortcut
        nsView.updateFromSettings()
        nsView.needsDisplay = true
    }
}
#endif
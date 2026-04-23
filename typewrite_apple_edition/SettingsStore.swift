// SettingsStore.swift
//
// UserDefaults-backed settings singleton. Persists all user preferences
// across app launches using the "typewriter." prefix. Acts as the single
// source of truth that CanvasView reads on every frame via updateFromSettings().
//
// Matches the X11 tw_x11_settings.c JSON file fields:
//   fontindex → fontIndex (0-8, default 2 = Special Elite)
//   background → themeIndex (0-9, default 0 = Dark)
//   cursormode → cursorMode (bar/blinkBar/block/blinkBlock/hidden)
//   linenumbers → gutterMode (off/ascending/descending)
//   pagemargins → pageMargins (bool, default true)
//   colsmargined → colsMargined (50-65, default 58)
//   typewriter → typewriterView (bool, default true)
//   wordwrap → wordWrap (bool, default true)
//   insertmode → insertMode (bool, default false)
//   soundenabled → soundEnabled (bool, default true)

import Foundation
import Combine

#if os(macOS)
import AppKit
#endif

enum CursorMode: Int, CaseIterable {
    case bar = 0
    case blinkBar = 1
    case block = 2
    case blinkBlock = 3
    case hidden = 4

    var isBlink: Bool { self == .blinkBar || self == .blinkBlock }
    var isBlock: Bool { self == .block || self == .blinkBlock }
    var isBar: Bool { self == .bar || self == .blinkBar }
    var displayName: String {
        switch self {
        case .bar: "Bar"
        case .blinkBar: "Blink Bar"
        case .block: "Block"
        case .blinkBlock: "Blink Block"
        case .hidden: "Hidden"
        }
    }
}

enum GutterMode: Int, CaseIterable {
    case off = 0
    case ascending = 1
    case descending = 2
}

@MainActor
class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// Same intervals as X11 `k_status_pulse_ms` (check-in toasts while writing).
    static let statusPulseIntervals: [TimeInterval] = [60, 300, 600, 900, 1800, 3600]
    static let statusPulseLabels = ["1 min", "5 min", "10 min", "15 min", "30 min", "1 hr"]
    static var statusPulseCount: Int { statusPulseIntervals.count }

    @Published var fontIndex: Int {
        didSet { save() }
    }
    @Published var themeIndex: Int {
        didSet { save() }
    }
    @Published var cursorMode: CursorMode {
        didSet { save() }
    }
    @Published var gutterMode: GutterMode {
        didSet { save() }
    }
    @Published var pageMargins: Bool {
        didSet { save() }
    }
    @Published var colsMargined: Int {
        didSet { save() }
    }
    @Published var typewriterView: Bool {
        didSet { save() }
    }
    @Published var wordWrap: Bool {
        didSet { save() }
    }
    @Published var insertMode: Bool {
        didSet { save() }
    }

    /// macOS: whether the in-window floating tool strip is visible (menu **View → Show Floating Toolbar**).
    @Published var macShowFloatingToolbar: Bool {
        didSet { save() }
    }

    #if os(macOS)
    /// macOS: 0 = solid window chrome (no vibrancy). 1…100 = stronger `NSVisualEffectView` material (more blur).
    @Published var macChromeBlurPercent: Int {
        didSet { save() }
    }

    /// macOS: 1 = opaque surround tint, 100 = fully transparent (no darkening on top of blur / solid fill).
    @Published var macChromeTransparencyPercent: Int {
        didSet { save() }
    }
    #endif

    @Published var soundEnabled: Bool {
        didSet { save() }
    }

    /// Index into `statusPulseIntervals` / `statusPulseLabels` (X11 `status_pulse` setting).
    @Published var statusPulseIndex: Int {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let prefix = "typewriter."

    init() {
        let d = UserDefaults.standard
        fontIndex = d.object(forKey: prefix + "fontIndex") as? Int ?? 2
        themeIndex = d.object(forKey: prefix + "background") as? Int ?? 0
        let cm = d.object(forKey: prefix + "cursorMode") as? Int ?? 3
        cursorMode = CursorMode(rawValue: cm) ?? .blinkBlock
        let gm = d.object(forKey: prefix + "gutterMode") as? Int ?? 0
        gutterMode = GutterMode(rawValue: gm) ?? .off
        pageMargins = d.object(forKey: prefix + "pageMargins") as? Bool ?? true
        colsMargined = d.object(forKey: prefix + "colsMargined") as? Int ?? 58
        typewriterView = d.object(forKey: prefix + "typewriterView") as? Bool ?? true
        wordWrap = d.object(forKey: prefix + "wordWrap") as? Bool ?? true
        insertMode = d.object(forKey: prefix + "insertMode") as? Bool ?? false
        macShowFloatingToolbar = d.object(forKey: prefix + "macShowFloatingToolbar") as? Bool ?? true
        #if os(macOS)
        let blur = d.object(forKey: prefix + "macChromeBlurPercent") as? Int ?? 0
        macChromeBlurPercent = min(max(blur, 0), 100)
        let trans = d.object(forKey: prefix + "macChromeTransparencyPercent") as? Int ?? 1
        macChromeTransparencyPercent = min(max(trans, 1), 100)
        #endif
        soundEnabled = d.object(forKey: prefix + "soundEnabled") as? Bool ?? true
        let sp = d.object(forKey: prefix + "status_pulse") as? Int ?? 0
        statusPulseIndex = min(max(0, sp), Self.statusPulseCount - 1)
    }

    func save() {
        defaults.set(fontIndex, forKey: prefix + "fontIndex")
        defaults.set(themeIndex, forKey: prefix + "background")
        defaults.set(cursorMode.rawValue, forKey: prefix + "cursorMode")
        defaults.set(gutterMode.rawValue, forKey: prefix + "gutterMode")
        defaults.set(pageMargins, forKey: prefix + "pageMargins")
        defaults.set(colsMargined, forKey: prefix + "colsMargined")
        defaults.set(typewriterView, forKey: prefix + "typewriterView")
        defaults.set(wordWrap, forKey: prefix + "wordWrap")
        defaults.set(insertMode, forKey: prefix + "insertMode")
        defaults.set(macShowFloatingToolbar, forKey: prefix + "macShowFloatingToolbar")
        #if os(macOS)
        defaults.set(macChromeBlurPercent, forKey: prefix + "macChromeBlurPercent")
        defaults.set(macChromeTransparencyPercent, forKey: prefix + "macChromeTransparencyPercent")
        #endif
        defaults.set(soundEnabled, forKey: prefix + "soundEnabled")
        defaults.set(statusPulseIndex, forKey: prefix + "status_pulse")
    }

    var statusPulseIntervalSeconds: TimeInterval {
        Self.statusPulseIntervals[min(max(0, statusPulseIndex), Self.statusPulseCount - 1)]
    }

    var statusPulseIntervalLabel: String {
        Self.statusPulseLabels[min(max(0, statusPulseIndex), Self.statusPulseCount - 1)]
    }

    var theme: PaperTheme {
        PaperTheme(rawValue: themeIndex) ?? .dark
    }

    #if os(macOS)
    /// Alpha for the theme surround tint (1 = opaque … 0 = invisible). `macChromeTransparencyPercent` 1→100 maps linearly.
    func macSurroundTintAlpha() -> CGFloat {
        let t = min(max(macChromeTransparencyPercent, 1), 100)
        return CGFloat(1.0 - Double(t - 1) / 99.0)
    }

    func macSurroundTintNSColor(theme: PaperTheme) -> NSColor {
        theme.surround.withAlphaComponent(macSurroundTintAlpha())
    }
    #endif
}
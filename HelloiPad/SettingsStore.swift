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

import UIKit

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
    }

    var theme: PaperTheme {
        PaperTheme(rawValue: themeIndex) ?? .dark
    }
}
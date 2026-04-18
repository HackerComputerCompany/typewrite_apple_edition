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
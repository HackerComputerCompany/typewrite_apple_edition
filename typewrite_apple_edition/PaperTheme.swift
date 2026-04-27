// PaperTheme.swift
//
// 10 colour schemes for the typewriter view, matching the X11 originals.
// Each theme has:
//   - paper: background colour of the text area
//   - ink: foreground text colour
//   - lineNumberInk: colour for line numbers in the gutter
//   - surround: colour for the margin area outside the paper
//   - rule: colour for the typewriter horizontal rule line and cursor bar
//
// The "Paper" (cream) theme is unique in having dark ink on light paper;
// all other themes use light ink on dark backgrounds.

import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit
typealias PlatformColor = NSColor
#endif

enum PaperTheme: Int, CaseIterable, Identifiable {
    case dark = 0
    case cream = 1
    case blue = 2
    case brown = 3
    case green = 4
    case maroon = 5
    case purple = 6
    case teal = 7
    case olive = 8
    case navy = 9

    var id: Int { rawValue }

    var paper: PlatformColor {
        switch self {
        case .dark:   PlatformColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1)
        case .cream:  PlatformColor(red: 0.941, green: 0.941, blue: 0.902, alpha: 1)
        case .blue:   PlatformColor(red: 0.0,   green: 0.188, blue: 0.376, alpha: 1)
        case .brown:  PlatformColor(red: 0.376, green: 0.188, blue: 0.0,   alpha: 1)
        case .green:  PlatformColor(red: 0.0,   green: 0.376, blue: 0.188, alpha: 1)
        case .maroon: PlatformColor(red: 0.376, green: 0.0,   blue: 0.188, alpha: 1)
        case .purple: PlatformColor(red: 0.188, green: 0.0,   blue: 0.376, alpha: 1)
        case .teal:   PlatformColor(red: 0.0,   green: 0.376, blue: 0.376, alpha: 1)
        case .olive:  PlatformColor(red: 0.376, green: 0.376, blue: 0.0,   alpha: 1)
        case .navy:   PlatformColor(red: 0.0,   green: 0.188, blue: 0.188, alpha: 1)
        }
    }

    var ink: PlatformColor {
        switch self {
        case .cream:  PlatformColor(red: 0.118, green: 0.110, blue: 0.094, alpha: 1)
        default:      PlatformColor(red: 0.941, green: 0.941, blue: 0.902, alpha: 1)
        }
    }

    var lineNumberInk: PlatformColor {
        switch self {
        case .cream:  PlatformColor(red: 0.376, green: 0.431, blue: 0.541, alpha: 1)
        default:      PlatformColor(red: 0.549, green: 0.588, blue: 0.686, alpha: 1)
        }
    }

    var surround: PlatformColor {
        PlatformColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)
    }

    var rule: PlatformColor {
        PlatformColor(red: 0.753, green: 0.094, blue: 0.094, alpha: 1)
    }

    var displayName: String {
        switch self {
        case .dark:   "Dark"
        case .cream:  "Paper"
        case .blue:   "Blue"
        case .brown:  "Brown"
        case .green:  "Green"
        case .maroon: "Maroon"
        case .purple: "Purple"
        case .teal:   "Teal"
        case .olive:  "Olive"
        case .navy:   "Navy"
        }
    }

    /// SwiftUI `Color` for editor chrome (platform-specific bridge).
    var surroundSwiftUI: Color {
        #if os(iOS)
        Color(uiColor: surround)
        #elseif os(macOS)
        Color(nsColor: surround)
        #else
        Color.gray
        #endif
    }

    /// Per-cell “inline” colour (independent of the main theme `ink` for red/blue highlights).
    func inlinePlatformInk(_ color: InkColor) -> PlatformColor {
        switch color {
        case .ink: return self.ink
        case .red: return PlatformColor(red: 0.88, green: 0.12, blue: 0.18, alpha: 1.0)
        case .blue: return PlatformColor(red: 0.2, green: 0.38, blue: 0.95, alpha: 1.0)
        }
    }
}
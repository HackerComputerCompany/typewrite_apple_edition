// TwCellTypes.swift
//
// Per-cell ink (inline “highlighter” colors) on top of the fixed character grid.

import Foundation

/// Inline ink on the grid. `.ink` follows the current paper theme’s main text colour.
enum InkColor: UInt8, CaseIterable, Codable, Equatable, Hashable {
    case ink = 0
    case red = 1
    case blue = 2

    var displayName: String {
        switch self {
        case .ink: return "Default"
        case .red: return "Red"
        case .blue: return "Blue"
        }
    }
}

struct TwCell: Equatable, Hashable {
    var ch: Character
    var ink: InkColor

    static let space = TwCell(" ", .ink)

    init(_ ch: Character, _ ink: InkColor) {
        self.ch = ch
        self.ink = ink
    }
}

/// Operations for replaying document content without lossy `String` serialization (used by `TwDoc.resize`).
enum TwResizeOp {
    case formFeed
    case newline
    case glyph(Character, InkColor)
}

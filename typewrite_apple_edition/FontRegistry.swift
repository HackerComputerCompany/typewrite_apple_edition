// FontRegistry.swift
//
// Loads 8 bundled TTF fonts at runtime via CTFontManagerRegisterFontsForURL,
// computes per-character cell metrics (width, height, ascent), and stores
// them as TypewriterFont structs. A 9th "System Mono" font is added as a
// fallback using the system monospaced font descriptor.
//
// Font-sound mapping (used by SoundManager):
//   0: Virgil        → virgil_pencil
//   1: Inter          → ui_tap
//   2: Special Elite   → typewriter_key / typewriter_carriage / typewriter_bell
//   3: Courier Prime   → typewriter_key / typewriter_carriage / typewriter_bell
//   4: VT323           → terminal_blip
//   5: Press Start 2P  → terminal_blip
//   6: IBM Plex Mono   → ibm_keyboard
//   7: Share Tech Mono → arcade_blip
//   8: System Mono     → simple_blip

import CoreText
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct TypewriterFont {
    let ctFont: CTFont
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let ascent: CGFloat
    let maxAdvance: CGFloat
    let displayName: String

    var lineHeight: CGFloat { cellHeight }
}

class FontRegistry {
    static let shared = FontRegistry()

    private(set) var fonts: [TypewriterFont] = []

    private init() {
        loadFonts()
    }

    private func loadFonts() {
        let fontSpecs: [(String, String, String)] = [
            ("Virgil", "virgil_fixed", "Virgil"),
            ("Inter", "inter", "Inter"),
            ("Special Elite", "SpecialElite-Regular", "Special Elite"),
            ("Courier Prime", "CourierPrime-Regular", "Courier Prime"),
            ("VT323", "VT323-Regular", "VT323"),
            ("Press Start 2P", "PressStart2P-Regular", "Press Start 2P"),
            ("IBM Plex Mono", "IBMPlexMono-Regular", "IBM Plex Mono"),
            ("Share Tech Mono", "ShareTechMono-Regular", "Share Tech Mono"),
        ]

        for (_, resName, displayName) in fontSpecs {
            var fontURL: URL?
            if let url = Bundle.main.url(forResource: resName, withExtension: "ttf", subdirectory: "Fonts") {
                fontURL = url
            } else if let url = Bundle.main.url(forResource: resName, withExtension: "ttf") {
                fontURL = url
            }

            if let url = fontURL {
                registerFont(from: url)
            } else {
                #if DEBUG
                print("[FontRegistry] Font file not found: \(resName).ttf")
                #endif
            }

            let ctFont = CTFontCreateWithName(resName as CFString, 24.0, nil)
            let metrics = computeMetrics(for: ctFont)

            fonts.append(TypewriterFont(
                ctFont: ctFont,
                cellWidth: metrics.cellWidth,
                cellHeight: metrics.cellHeight,
                ascent: metrics.ascent,
                maxAdvance: metrics.maxAdvance,
                displayName: displayName
            ))
        }

        let systemFont: CTFont = {
            #if os(iOS)
            let mono = UIFontDescriptor
                .preferredFontDescriptor(withTextStyle: .body)
                .withDesign(.monospaced) ?? UIFontDescriptor
                .preferredFontDescriptor(withTextStyle: .body)
            return CTFontCreateWithName(mono.postscriptName as CFString, 24.0, nil)
            #elseif os(macOS)
            let ns = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            return CTFontCreateWithName(ns.fontName as CFString, 24.0, nil)
            #else
            return CTFontCreateWithName("Menlo" as CFString, 24.0, nil)
            #endif
        }()
        let sysMetrics = computeMetrics(for: systemFont)
        fonts.append(TypewriterFont(
            ctFont: systemFont,
            cellWidth: sysMetrics.cellWidth,
            cellHeight: sysMetrics.cellHeight,
            ascent: sysMetrics.ascent,
            maxAdvance: sysMetrics.maxAdvance,
            displayName: "System Mono"
        ))
    }

    private func computeMetrics(for ctFont: CTFont) -> (cellWidth: CGFloat, cellHeight: CGFloat, ascent: CGFloat, maxAdvance: CGFloat) {
        let ascent = CTFontGetAscent(ctFont)
        let descent = CTFontGetDescent(ctFont)
        let leading = CTFontGetLeading(ctFont)
        let lineH = ceil(ascent + descent + leading)

        var maxAdv: CGFloat = 0
        for codeUnit in 32...126 {
            var ch = UniChar(codeUnit)
            var glyph = CGGlyph.zero
            CTFontGetGlyphsForCharacters(ctFont, &ch, &glyph, 1)
            if glyph != CGGlyph.zero {
                var advances = CGSize.zero
                CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advances, 1)
                maxAdv = max(maxAdv, advances.width)
            }
        }
        if maxAdv == 0 {
            maxAdv = CTFontGetSize(ctFont) * 0.6
        }

        let cellW = ceil(maxAdv) + 0.5
        let cellH = lineH
        return (cellWidth: cellW, cellHeight: cellH, ascent: ascent, maxAdvance: maxAdv)
    }

    private func registerFont(from url: URL) {
        var error: Unmanaged<CFError>?
        let result = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !result {
            #if DEBUG
            if let err = error?.takeRetainedValue() {
                print("[FontRegistry] Failed to register \(url.lastPathComponent): \(err)")
            }
            #endif
        }
    }

    func font(at index: Int) -> TypewriterFont {
        fonts[fonts.indices.contains(index) ? index : 2]
    }
}
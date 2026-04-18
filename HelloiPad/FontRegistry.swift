import UIKit
import CoreText

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
            ("Inter", "Inter-Regular", "Inter"),
            ("Special Elite", "SpecialElite-Regular", "Special Elite"),
            ("Courier Prime", "CourierPrime-Regular", "Courier Prime"),
            ("VT323", "VT323-Regular", "VT323"),
            ("Press Start 2P", "PressStart2P-Regular", "Press Start 2P"),
            ("IBM Plex Mono", "IBMPlexMono-Regular", "IBM Plex Mono"),
            ("Share Tech Mono", "ShareTechMono-Regular", "Share Tech Mono"),
        ]

        for (_, resName, displayName) in fontSpecs {
            if let url = Bundle.main.url(forResource: resName, withExtension: "ttf", subdirectory: "Fonts") {
                registerFont(from: url)
            } else if let url = Bundle.main.url(forResource: resName, withExtension: "ttf") {
                registerFont(from: url)
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

        let mono = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .body)
            .withDesign(.monospaced) ?? UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .body)
        let systemFont = CTFontCreateWithName(mono.postscriptName as CFString, 18.0, nil)
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

        let cellW = ceil(maxAdv) + 1.0
        let cellH = lineH
        return (cellWidth: cellW, cellHeight: cellH, ascent: ascent, maxAdvance: maxAdv)
    }

    private func registerFont(from url: URL) {
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }

    func font(at index: Int) -> TypewriterFont {
        fonts[fonts.indices.contains(index) ? index : 2]
    }
}
// TwBinaryArchive.swift
//
// Binary document format (.twd) — structure + per-cell ink + optional session metrics.
// Plain .txt remains supported for import/export of text only (all default ink).

import Foundation

/// Session / stats block stored inside a binary document (optional for v1 readers).
struct TwSessionMetadata: Codable, Equatable {
    var sessionTypingUnits: UInt64
    var emaMsPerChar: Double
    var savedAt: Date?

    static let empty = TwSessionMetadata(sessionTypingUnits: 0, emaMsPerChar: 0, savedAt: nil)
}

enum TwBinaryFormatError: Error {
    case badMagic
    case unsupportedVersion(UInt32)
    case corruptPayload
}

/// Version 1 layout:
///   "TWDB" (4) | version u32 BE (1) | flags u32 BE (0)
///   | metaLength u32 BE | meta JSON UTF-8 (TwSessionMetadata)
///   | cols u16 BE | rows u16 BE | pageCount u32 BE
///   For each page: cellCount u32 BE (= cols*rows), then per cell: ink u8 | utf8Count u8 | utf8 bytes (1…8 typical)
enum TwBinaryArchiveV1 {
    static let magic = "TWDB"
    static let version: UInt32 = 1

    static func encode(doc: TwDoc, session: TwSessionMetadata) throws -> Data {
        var out = Data()
        out.append(contentsOf: magic.utf8)
        out.appendUInt32BE(Self.version)
        out.appendUInt32BE(0) // flags

        let metaJSON = try JSONEncoder().encode(session)
        out.appendUInt32BE(UInt32(metaJSON.count))
        out.append(metaJSON)

        out.appendUInt16BE(UInt16(doc.cols))
        out.appendUInt16BE(UInt16(doc.rows))
        out.appendUInt32BE(UInt32(doc.pages.count))

        for page in doc.pages {
            let n = doc.cols * doc.rows
            out.appendUInt32BE(UInt32(n))
            for i in 0..<n {
                let cell = page.cells[i]
                out.append(cell.ink.rawValue)
                try appendCharacter(cell.ch, to: &out)
            }
        }
        return out
    }

    static func decode(_ data: Data) throws -> (doc: TwDoc, session: TwSessionMetadata) {
        guard data.count >= 4 + 4 + 4 + 4 else { throw TwBinaryFormatError.corruptPayload }
        let magic = String(data: data[0..<4], encoding: .ascii)
        guard magic == Self.magic else { throw TwBinaryFormatError.badMagic }
        var o = 4
        let ver = data.readUInt32BE(at: o)
        o += 4
        guard ver == 1 else { throw TwBinaryFormatError.unsupportedVersion(ver) }
        o += 4 // flags
        let metaLen = Int(data.readUInt32BE(at: o))
        o += 4
        guard data.count >= o + metaLen else { throw TwBinaryFormatError.corruptPayload }
        let metaData = data[o..<(o + metaLen)]
        o += metaLen
        let session = (try? JSONDecoder().decode(TwSessionMetadata.self, from: Data(metaData))) ?? .empty

        guard data.count >= o + 2 + 2 + 4 else { throw TwBinaryFormatError.corruptPayload }
        let cols = Int(data.readUInt16BE(at: o))
        o += 2
        let rows = Int(data.readUInt16BE(at: o))
        o += 2
        let pageCount = Int(data.readUInt32BE(at: o))
        o += 4
        guard cols > 0, rows > 0, pageCount > 0 else { throw TwBinaryFormatError.corruptPayload }

        var doc = TwDoc(cols: cols, rows: rows)
        doc.pages.removeAll(keepingCapacity: true)
        for _ in 0..<pageCount {
            guard data.count >= o + 4 else { throw TwBinaryFormatError.corruptPayload }
            let cellCount = Int(data.readUInt32BE(at: o))
            o += 4
            guard cellCount == cols * rows else { throw TwBinaryFormatError.corruptPayload }
            var p = TwCore(cols: cols, rows: rows)
            for i in 0..<cellCount {
                guard data.count >= o + 1 else { throw TwBinaryFormatError.corruptPayload }
                let inkRaw = data[o]
                o += 1
                let ink = InkColor(rawValue: inkRaw) ?? .ink
                let (ch, adv) = try readCharacter(from: data, at: o)
                o += adv
                p.cells[i] = TwCell(ch, ink)
            }
            doc.pages.append(p)
        }
        doc.positionCursorAtDocumentEnd()
        return (doc, session)
    }

    private static func appendCharacter(_ ch: Character, to out: inout Data) throws {
        let s = String(ch)
        let utf8 = Array(s.utf8)
        guard utf8.count <= 16 else { throw TwBinaryFormatError.corruptPayload }
        out.append(UInt8(utf8.count))
        out.append(contentsOf: utf8)
    }

    private static func readCharacter(from data: Data, at o: Int) throws -> (Character, Int) {
        guard data.count > o else { throw TwBinaryFormatError.corruptPayload }
        let n = Int(data[o])
        let start = o + 1
        guard n > 0, data.count >= start + n else { throw TwBinaryFormatError.corruptPayload }
        let sub = data[start..<(start + n)]
        guard let str = String(bytes: sub, encoding: .utf8), let ch = str.first else {
            throw TwBinaryFormatError.corruptPayload
        }
        return (ch, 1 + n)
    }
}

// MARK: - Data helpers (big-endian)

private extension Data {
    mutating func appendUInt32BE(_ v: UInt32) {
        append(UInt8((v >> 24) & 0xff))
        append(UInt8((v >> 16) & 0xff))
        append(UInt8((v >> 8) & 0xff))
        append(UInt8(v & 0xff))
    }

    mutating func appendUInt16BE(_ v: UInt16) {
        append(UInt8((v >> 8) & 0xff))
        append(UInt8(v & 0xff))
    }

    func readUInt32BE(at o: Int) -> UInt32 {
        let a = UInt32(self[o])
        let b = UInt32(self[o + 1])
        let c = UInt32(self[o + 2])
        let d = UInt32(self[o + 3])
        return (a << 24) | (b << 16) | (c << 8) | d
    }

    func readUInt16BE(at o: Int) -> UInt16 {
        let a = UInt16(self[o])
        let b = UInt16(self[o + 1])
        return (a << 8) | b
    }
}

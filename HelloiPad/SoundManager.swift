import AVFoundation

@MainActor
class SoundManager {
    static let shared = SoundManager()

    private var players: [String: AVAudioPlayer] = [:]
    private let playerPool = NSCache<NSString, AVAudioPlayer>()
    private var reversedDataCache: [String: Data] = [:]

    enum SoundName: String, CaseIterable {
        case virgilPencil = "virgil_pencil"
        case uiTap = "ui_tap"
        case typewriterKey = "typewriter_key"
        case typewriterCarriage = "typewriter_carriage"
        case typewriterBell = "typewriter_bell"
        case terminalBlip = "terminal_blip"
        case ibmKeyboard = "ibm_keyboard"
        case arcadeBlip = "arcade_blip"
        case simpleBlip = "simple_blip"
    }

    private init() {}

    func preload() {
        for name in SoundName.allCases {
            load(name)
        }
        playerPool.countLimit = 16
    }

    private func load(_ name: SoundName) {
        guard players[name.rawValue] == nil else { return }
        guard let url = Bundle.main.url(forResource: name.rawValue, withExtension: "wav", subdirectory: "Sounds") else {
            if let url = Bundle.main.url(forResource: name.rawValue, withExtension: "wav") {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    players[name.rawValue] = player
                }
            }
            return
        }
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.prepareToPlay()
            players[name.rawValue] = player
        }
    }

    func playKey(for fontIndex: Int) {
        let name: SoundName
        switch fontIndex {
        case 0: name = .virgilPencil
        case 1: name = .uiTap
        case 2, 3: name = .typewriterKey
        case 4, 5: name = .terminalBlip
        case 6: name = .ibmKeyboard
        case 7: name = .arcadeBlip
        default: name = .simpleBlip
        }
        playPooled(name)
    }

    func playDelete(for fontIndex: Int) {
        let name: SoundName
        switch fontIndex {
        case 0: name = .virgilPencil
        case 1: name = .uiTap
        case 2, 3: name = .typewriterKey
        case 4, 5: name = .terminalBlip
        case 6: name = .ibmKeyboard
        case 7: name = .arcadeBlip
        default: name = .simpleBlip
        }
        playPooledReversed(name)
    }

    func playCarriage(for fontIndex: Int) {
        guard fontIndex == 2 || fontIndex == 3 else { return }
        playPooled(.typewriterCarriage)
    }

    func playBell(for fontIndex: Int) {
        guard fontIndex == 2 || fontIndex == 3 else { return }
        playPooled(.typewriterBell)
    }

    private func playPooled(_ name: SoundName) {
        guard let base = players[name.rawValue] else { return }
        guard let url = base.url else { return }
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = 1.0
            player.play()
            playerPool.setObject(player, forKey: "\(name.rawValue)-\(UUID().uuidString)" as NSString)
        }
    }

    private func playPooledReversed(_ name: SoundName) {
        guard let base = players[name.rawValue] else { return }
        guard let url = base.url else { return }

        let cacheKey = name.rawValue + "_rev"
        if let reversedData = reversedDataCache[cacheKey] {
            if let player = try? AVAudioPlayer(data: reversedData) {
                player.volume = 0.8
                player.play()
                playerPool.setObject(player, forKey: "\(cacheKey)-\(UUID().uuidString)" as NSString)
            }
            return
        }

        guard let originalData = try? Data(contentsOf: url),
              let reversed = reverseWAV(originalData) else {
            playPooled(name)
            return
        }

        reversedDataCache[cacheKey] = reversed
        if let player = try? AVAudioPlayer(data: reversed) {
            player.volume = 0.8
            player.play()
            playerPool.setObject(player, forKey: "\(cacheKey)-\(UUID().uuidString)" as NSString)
        }
    }

    private func reverseWAV(_ data: Data) -> Data? {
        guard data.count > 44 else { return nil }

        let header = data[0..<44]
        var audioData = Data(data[44...])

        let fmtChunkOffset = 12
        guard fmtChunkOffset + 8 <= header.count else { return nil }
        let fmtChunkID = String(data: header[fmtChunkOffset..<(fmtChunkOffset+4)], encoding: .ascii)
        guard fmtChunkID == "fmt " else { return nil }

        let audioFormat = Int(header[fmtChunkOffset + 8]) | (Int(header[fmtChunkOffset + 9]) << 8)
        guard audioFormat == 1 else { return nil }

        let numChannels = Int(header[fmtChunkOffset + 10]) | (Int(header[fmtChunkOffset + 11]) << 8)
        let bitsPerSample = Int(header[fmtChunkOffset + 14]) | (Int(header[fmtChunkOffset + 15]) << 8)
        let bytesPerSample = bitsPerSample / 8
        let frameSize = bytesPerSample * numChannels

        guard frameSize > 0, audioData.count % frameSize == 0 else { return nil }

        let numFrames = audioData.count / frameSize
        var reversed = Data(capacity: audioData.count)
        for i in stride(from: numFrames - 1, through: 0, by: -1) {
            let offset = i * frameSize
            reversed.append(audioData[offset..<(offset + frameSize)])
        }

        return header + reversed
    }
}
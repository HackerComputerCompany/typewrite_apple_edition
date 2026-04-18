import AVFoundation

@MainActor
class SoundManager {
    static let shared = SoundManager()

    private var players: [String: AVAudioPlayer] = [:]
    private let playerPool = NSCache<NSString, AVAudioPlayer>()

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
}
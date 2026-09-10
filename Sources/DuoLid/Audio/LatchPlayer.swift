import AVFoundation
import DuoLidCore

@MainActor
final class LatchPlayer {
    private var players: [LatchTone: AVAudioPlayer] = [:]
    var onError: ((String) -> Void)?

    init() {
        for tone in LatchTone.allCases {
            if let player = try? AVAudioPlayer(data: LatchSynthesis.waveData(tone: tone)) {
                player.prepareToPlay()
                players[tone] = player
            }
        }
    }

    @discardableResult
    func play(_ tone: LatchTone, volume: Double) -> Bool {
        guard let player = players[tone] else {
            onError?("The sound could not be prepared. Try reopening DuoLid.")
            return false
        }
        player.stop()
        player.currentTime = 0
        player.volume = Float(volume)
        let success = player.play()
        if !success { onError?("Audio output is unavailable. Check your Mac’s sound output.") }
        return success
    }

    func stop() { for player in players.values { player.stop() } }
}

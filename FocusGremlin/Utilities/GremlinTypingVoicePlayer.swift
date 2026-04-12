import AVFoundation
import Foundation

/// Звуки реплики: длинные — `gremlin_typing_voice.mp3`; 1–2 слова — `gremlin_short_words.mp3`; смех — `gremlin_giggle.mp3`.
@MainActor
final class GremlinTypingVoicePlayer {
    static let shared = GremlinTypingVoicePlayer()

    private var typingPlayer: AVAudioPlayer?
    private var shortWordsPlayer: AVAudioPlayer?
    private var gigglePlayer: AVAudioPlayer?
    private var spitPlayer: AVAudioPlayer?

    private init() {}

    /// Один раз проигрывает файл, если звуки включены и есть текст для печати (3+ слов или длиннее по смыслу набора).
    func playTypingVoiceOnceIfAllowed(soundsEnabled: Bool, textNonEmpty: Bool) {
        stop()
        guard soundsEnabled, textNonEmpty else { return }
        guard let url = Bundle.main.url(forResource: "gremlin_typing_voice", withExtension: "mp3") else {
            AppLogger.app.debug("gremlin_typing_voice.mp3 missing from bundle")
            return
        }
        typingPlayer = makePlayer(url: url)
        typingPlayer?.play()
    }

    /// Реплика из 1–2 слов (как в лимите цитаты): один короткий звук гоблина вместо ленты набора.
    func playShortWordsGoblinOnceIfAllowed(soundsEnabled: Bool, wordCount: Int) {
        stop()
        guard soundsEnabled, (1...2).contains(wordCount) else { return }
        guard let url = Bundle.main.url(forResource: "gremlin_short_words", withExtension: "mp3") else {
            AppLogger.app.debug("gremlin_short_words.mp3 missing from bundle")
            return
        }
        shortWordsPlayer = makePlayer(url: url)
        shortWordsPlayer?.play()
    }

    /// Смех / хихиканье (стиль реплики `.giggle`).
    func playGiggleOnceIfAllowed(soundsEnabled: Bool) {
        stop()
        guard soundsEnabled else { return }
        guard let url = Bundle.main.url(forResource: "gremlin_giggle", withExtension: "mp3") else {
            AppLogger.app.debug("gremlin_giggle.mp3 missing from bundle")
            return
        }
        gigglePlayer = makePlayer(url: url)
        gigglePlayer?.play()
    }

    /// Короткий харчок/плевок между цитатами.
    func playSpitOnceIfAllowed(soundsEnabled: Bool) {
        stop()
        guard soundsEnabled else { return }
        guard let url = Bundle.main.url(forResource: "gremlin_spit", withExtension: "mp3") else {
            AppLogger.app.debug("gremlin_spit.mp3 missing from bundle")
            return
        }
        spitPlayer = makePlayer(url: url)
        spitPlayer?.volume = 0.98
        spitPlayer?.play()
    }

    func stop() {
        typingPlayer?.stop()
        typingPlayer = nil
        shortWordsPlayer?.stop()
        shortWordsPlayer = nil
        gigglePlayer?.stop()
        gigglePlayer = nil
        spitPlayer?.stop()
        spitPlayer = nil
    }

    private func makePlayer(url: URL) -> AVAudioPlayer? {
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = 0
            p.volume = 0.95
            p.prepareToPlay()
            return p
        } catch {
            AppLogger.app.error("Gremlin voice: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

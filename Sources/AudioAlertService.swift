import AVFoundation
import CoreLocation
import SwiftUI

// MARK: - AudioAlertService

final class AudioAlertService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AudioAlertService()

    private let synthesizer = AVSpeechSynthesizer()

    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoice: AVSpeechSynthesisVoice?
    @Published var isSpeaking = false

    // Radars déjà annoncés : "id-far" ou "id-close"
    private var announced: Set<String> = []
    private let voiceKey = "selectedVoiceIdentifier"

    override init() {
        super.init()
        synthesizer.delegate = self

        // Voix françaises triées : premium d'abord
        availableVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("fr") }
            .sorted {
                let a = ($0.quality.rawValue >= AVSpeechSynthesisVoiceQuality.enhanced.rawValue) ? 0 : 1
                let b = ($1.quality.rawValue >= AVSpeechSynthesisVoiceQuality.enhanced.rawValue) ? 0 : 1
                return a < b || (a == b && $0.name < $1.name)
            }

        // Restore last selection
        if let id = UserDefaults.standard.string(forKey: voiceKey),
           let v = AVSpeechSynthesisVoice(identifier: id) {
            selectedVoice = v
        } else {
            selectedVoice = availableVoices.first
                ?? AVSpeechSynthesisVoice(language: "fr-FR")
        }

        configureAudioSession()
    }

    // MARK: - Public

    func speak(_ text: String) {
        configureAudioSession()
        synthesizer.stopSpeaking(at: .word)
        let u = AVSpeechUtterance(string: text)
        u.voice  = selectedVoice
        u.rate   = AVSpeechUtteranceDefaultSpeechRate * 0.92
        u.volume = 1.0
        u.postUtteranceDelay = 0.15
        synthesizer.speak(u)
    }

    func testAlert() {
        speak("Alerte radar. Radar fixe dans cinq cents mètres, vitesse limitée à quatre-vingt kilomètres heure.")
    }

    func announceReady() {
        speak("Application prête pour utilisation.")
    }

    func selectVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoice = voice
        UserDefaults.standard.set(voice.identifier, forKey: voiceKey)
    }

    // MARK: - Proximity check (appelé depuis ContentView à chaque update GPS)

    func checkProximity(radars: [Radar], location: CLLocation) {
        let course = location.course  // -1 si indisponible
        for radar in radars {
            let dist = location.distance(from: radar.location)

            // Tiers d'annonce : 500 m puis 200 m
            let tier: String
            switch dist {
            case ..<220:  tier = "close"
            case ..<520:  tier = "far"
            default: continue
            }

            let key = "\(radar.id)-\(tier)"
            guard !announced.contains(key) else { continue }

            // Vérifier qu'on se dirige vers le radar (±70°) si le cap est dispo
            if course >= 0 {
                let bearing = location.bearing(to: radar.coordinate)
                let diff = abs(angleDiff(from: course, to: bearing))
                guard diff < 70 else { continue }
            }

            announced.insert(key)
            let distText = tier == "close" ? "deux cents mètres" : "cinq cents mètres"
            var msg = "\(radar.kind.voiceLabel) dans \(distText)"
            if let vma = radar.vma { msg += ", vitesse limitée à \(vma) kilomètres heure" }
            speak(msg)
        }

        // Nettoyer les radars devenus lointains
        let ids = Set(radars.map { $0.id })
        announced = Set(announced.filter { key in
            let id = key.components(separatedBy: "-").dropLast().joined(separator: "-")
            return ids.contains(id)
        })
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    // MARK: - Private

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .voicePrompt,
            options: [.duckOthers, .mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func angleDiff(from a: Double, to b: Double) -> Double {
        var d = b - a
        while d >  180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }
}

// MARK: - RadarKind voiceLabel

extension RadarKind {
    var voiceLabel: String {
        switch self {
        case .fixe:        "Radar fixe"
        case .discriminant:"Radar discriminant"
        case .feuRouge:    "Radar feu rouge"
        case .vitMoyenne:  "Radar de vitesse moyenne"
        case .pn:          "Radar passage à niveau"
        case .itineraire:  "Tronçon contrôlé"
        }
    }
}

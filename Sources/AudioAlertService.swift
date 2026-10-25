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

    private var announced: Set<String> = []
    private var prevDist:  [String: CLLocationDistance] = [:]
    private let voiceKey = "selectedVoiceIdentifier"

    override init() {
        super.init()
        synthesizer.delegate = self

        availableVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("fr") }
            .sorted {
                let a = ($0.quality.rawValue >= AVSpeechSynthesisVoiceQuality.enhanced.rawValue) ? 0 : 1
                let b = ($1.quality.rawValue >= AVSpeechSynthesisVoiceQuality.enhanced.rawValue) ? 0 : 1
                return a < b || (a == b && $0.name < $1.name)
            }

        if let id = UserDefaults.standard.string(forKey: voiceKey),
           let v = AVSpeechSynthesisVoice(identifier: id) {
            selectedVoice = v
        } else {
            selectedVoice = availableVoices.first ?? AVSpeechSynthesisVoice(language: "fr-FR")
        }

        // Category seulement — pas d'activation tant qu'on ne parle pas
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers]
        )
    }

    // MARK: - Public

    func speak(_ text: String) {
        // Activer la session juste avant de parler → pas de ducking permanent
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.stopSpeaking(at: .word)
        let u = AVSpeechUtterance(string: text)
        u.voice              = selectedVoice
        u.rate               = AVSpeechUtteranceDefaultSpeechRate * 0.92
        u.volume             = 1.0
        u.postUtteranceDelay = 0.15
        synthesizer.speak(u)
    }

    func testAlert() {
        speak("Alerte radar. Radar fixe dans trois cents mètres, vitesse limitée à quatre-vingt kilomètres heure.")
    }

    func announceReady() {
        speak("Application prête pour utilisation.")
    }

    func selectVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoice = voice
        UserDefaults.standard.set(voice.identifier, forKey: voiceKey)
    }

    // MARK: - Proximity check

    func checkProximity(radars: [Radar], location: CLLocation) {
        let course = location.course  // −1 si indisponible

        for radar in radars {
            let dist     = location.distance(from: radar.location)
            let previous = prevDist[radar.id] ?? .infinity
            prevDist[radar.id] = dist

            // ── Approche seulement (distance décroissante avec 25 m d'hystérésis) ──
            guard dist < previous - 25 else { continue }

            // ── Tiers 600 m / 300 m / 100 m ─────────────────────────────────────
            let tier: String
            switch dist {
            case ..<110:  tier = "veryclose"
            case ..<320:  tier = "close"
            case ..<620:  tier = "far"
            default:      continue
            }

            let key = "\(radar.id)-\(tier)"
            guard !announced.contains(key) else { continue }

            // ── Cap : cône ±45° ──────────────────────────────────────────────────
            if course >= 0 {
                let bearing = location.bearing(to: radar.coordinate)
                guard abs(angleDiff(from: course, to: bearing)) < 45 else { continue }
            } else if radar.kind == .feuRouge || radar.kind == .pn {
                // Feu rouge / PN = radar urbain ponctuel → cap GPS obligatoire
                continue
            }

            // Marquer aussi tous les tiers plus lointains pour éviter les faux
            // positifs en s'éloignant (app démarrée proche du radar)
            announced.insert(key)
            if tier == "veryclose" {
                announced.insert("\(radar.id)-close")
                announced.insert("\(radar.id)-far")
            } else if tier == "close" {
                announced.insert("\(radar.id)-far")
            }

            let distText: String
            switch tier {
            case "veryclose": distText = "cent mètres"
            case "close":     distText = "trois cents mètres"
            default:          distText = "six cents mètres"
            }
            var msg = "\(radar.kind.voiceLabel) dans \(distText)"
            if let vma = radar.vma { msg += ", vitesse limitée à \(vma) kilomètres heure" }
            speak(msg)
        }

        // Libérer les clés des radars > 1 km (permet la réalerte au prochain passage)
        let nearbyIds = Set(radars.filter { location.distance(from: $0.location) < 1_000 }.map(\.id))
        announced    = announced.filter { nearbyIds.contains(idFromKey($0)) }
        let allIds   = Set(radars.map(\.id))
        prevDist     = prevDist.filter { allIds.contains($0.key) }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
        // Désactiver → la musique reprend immédiatement
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Helpers

    private func angleDiff(from a: Double, to b: Double) -> Double {
        var d = b - a
        while d >  180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    private func idFromKey(_ key: String) -> String {
        key.components(separatedBy: "-").dropLast().joined(separator: "-")
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

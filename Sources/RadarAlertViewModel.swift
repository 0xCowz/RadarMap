import AudioToolbox
import Combine
import CoreLocation
import Foundation
import UIKit

/// Surveille la position et déclenche une alerte quand on s'approche d'un radar à < 300 m.
final class RadarAlertViewModel: ObservableObject {
    @Published var triggeredRadar: Radar?
    @Published var triggeredDistance: Double?

    private var alreadyAlerted = Set<String>()  // IDs déjà signalés
    private var bag = Set<AnyCancellable>()
    private let alertDistance: CLLocationDistance = 300  // mètres

    func start(store: RadarStore) {
        LocationService.shared.$location
            .compactMap { $0 }
            .throttle(for: 4, scheduler: DispatchQueue.global(qos: .utility), latest: true)
            .sink { [weak self, weak store] loc in
                guard let self, let store else { return }
                self.check(location: loc, store: store)
            }
            .store(in: &bag)
    }

    private func check(location: CLLocation, store: RadarStore) {
        // Réinitialise les alertes si on s'est éloigné (> 600 m de tous les radars alertés)
        let nearby = store.nearest(to: location, limit: 50)
        let nearIDs = Set(nearby.filter { $0.distance < 600 }.map { $0.radar.id })
        alreadyAlerted = alreadyAlerted.intersection(nearIDs)

        // Cherche le radar le plus proche non encore alerté
        guard let closest = nearby.first(where: {
            $0.distance < alertDistance && !alreadyAlerted.contains($0.radar.id)
        }) else { return }

        alreadyAlerted.insert(closest.radar.id)

        DispatchQueue.main.async {
            self.triggeredRadar   = closest.radar
            self.triggeredDistance = closest.distance
            self.playAlert()
        }
    }

    private func playAlert() {
        // Haptic fort
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let gen2 = UIImpactFeedbackGenerator(style: .heavy)
            gen2.impactOccurred()
        }
        // Son système (bip d'alerte)
        AudioServicesPlaySystemSound(1005)
    }
}

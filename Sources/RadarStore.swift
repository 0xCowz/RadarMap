import CoreLocation
import Foundation

/// Données + filtres, partagés entre l'iPhone et CarPlay.
final class RadarStore: ObservableObject {
    static let shared = RadarStore()

    let all: [Radar] = Radar.loadBundled()
    private let key = "enabledKinds"

    @Published var enabledKinds: Set<RadarKind> {
        didSet { UserDefaults.standard.set(enabledKinds.map(\.rawValue), forKey: key) }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: key)?.compactMap(RadarKind.init(rawValue:))
        enabledKinds = saved.map(Set.init) ?? Set(RadarKind.allCases)
    }

    var filtered: [Radar] { all.filter { enabledKinds.contains($0.kind) } }

    func count(of kind: RadarKind) -> Int { all.filter { $0.kind == kind }.count }

    func toggle(_ kind: RadarKind) {
        if enabledKinds.contains(kind) { enabledKinds.remove(kind) } else { enabledKinds.insert(kind) }
    }

    func nearest(to location: CLLocation, limit: Int) -> [(radar: Radar, distance: CLLocationDistance)] {
        filtered.map { (radar: $0, distance: $0.location.distance(from: location)) }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map { $0 }
    }
}

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()
    private let manager = CLLocationManager()
    @Published var location: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 50
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) { location = l.last }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways {
            m.startUpdatingLocation()
        }
    }
}

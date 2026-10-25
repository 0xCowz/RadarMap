import CoreLocation
import Foundation

/// Données + filtres, partagés entre l'iPhone et CarPlay.
final class RadarStore: ObservableObject {
    static let shared = RadarStore()

    @Published var all: [Radar] = Radar.loadBundled()   // Démarrage immédiat sur le CSV
    @Published var isLoadingRemote = false
    @Published var dataSource: String = "CSV embarqué"
    @Published var lastUpdated: Date = Date()
    private let key = "enabledKinds"

    @Published var enabledKinds: Set<RadarKind> {
        didSet { UserDefaults.standard.set(enabledKinds.map(\.rawValue), forKey: key) }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: key)?.compactMap(RadarKind.init(rawValue:))
        enabledKinds = saved.map(Set.init) ?? Set(RadarKind.allCases)
        Task { await refreshFromAPI() }
    }

    @MainActor
    func refreshFromAPI() async {
        isLoadingRemote = true
        let remote = await Radar.loadAll()
        if !remote.isEmpty {
            all = remote
            dataSource = "API NAS"
            lastUpdated = Date()
        }
        isLoadingRemote = false
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
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter  = 20
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            // Upgrade to Always so background tracking works
            manager.requestAlwaysAuthorization()
            enableBackground()
            manager.startUpdatingLocation()
        case .authorizedAlways:
            enableBackground()
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    private func enableBackground() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        location = l.last
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorizedAlways:
            enableBackground()
            m.startUpdatingLocation()
        case .authorizedWhenInUse:
            m.startUpdatingLocation()
        default:
            break
        }
    }
}

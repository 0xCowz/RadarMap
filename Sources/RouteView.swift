import Combine
import CoreLocation
import MapKit
import SwiftUI

// MARK: - RouteViewModel

@MainActor
final class RouteViewModel: ObservableObject {
    @Published var query = ""
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false
    @Published var route: MKRoute?
    @Published var routeRadars: [Radar] = []
    @Published var showConfirmation = false
    @Published var error: String?

    private let completer = MKLocalSearchCompleter()
    private var delegate: CompleterDelegate?
    private var debounce: AnyCancellable?

    init() {
        let d = CompleterDelegate { [weak self] results in
            self?.suggestions = results
        }
        delegate      = d
        completer.delegate   = d
        completer.resultTypes = .address
    }

    func search(for text: String) {
        guard !text.isEmpty else { suggestions = []; return }
        completer.queryFragment = text
    }

    func selectSuggestion(_ completion: MKLocalSearchCompletion, store: RadarStore) async {
        isSearching = true
        error = nil
        defer { isSearching = false }

        // Geocode the suggestion
        let req = MKLocalSearch.Request(completion: completion)
        do {
            let result = try await MKLocalSearch(request: req).start()
            guard let destItem = result.mapItems.first else {
                error = "Adresse introuvable"
                return
            }
            // Route depuis position actuelle
            let origin: MKMapItem
            if let loc = LocationService.shared.location {
                let placemark = MKPlacemark(coordinate: loc.coordinate)
                origin = MKMapItem(placemark: placemark)
            } else {
                origin = MKMapItem.forCurrentLocation()
            }

            let dirReq            = MKDirections.Request()
            dirReq.source         = origin
            dirReq.destination    = destItem
            dirReq.transportType  = .automobile
            dirReq.requestsAlternateRoutes = false

            let dirs = MKDirections(request: dirReq)
            let response = try await dirs.calculate()
            guard let mkRoute = response.routes.first else {
                error = "Aucun itinéraire trouvé"
                return
            }
            route = mkRoute

            // Compter les radars le long du tracé (corridor ±200 m)
            let coords = mkRoute.polyline.coordinates
            var found = Set<String>()
            for radar in store.filtered {
                let radarLoc = radar.location
                // Vérification rapide : le radar est-il dans la bbox de l'itinéraire ?
                let minLat = coords.map(\.latitude).min() ?? 0
                let maxLat = coords.map(\.latitude).max() ?? 0
                let minLon = coords.map(\.longitude).min() ?? 0
                let maxLon = coords.map(\.longitude).max() ?? 0
                guard radar.coordinate.latitude  >= minLat - 0.01,
                      radar.coordinate.latitude  <= maxLat + 0.01,
                      radar.coordinate.longitude >= minLon - 0.01,
                      radar.coordinate.longitude <= maxLon + 0.01 else { continue }

                // Distance minimale de chaque segment du tracé
                let threshold: CLLocationDistance = 200
                var onRoute = false
                for i in 0..<(coords.count - 1) {
                    let pt = closestPointOnSegment(
                        from: radar.coordinate,
                        segA: coords[i], segB: coords[i + 1])
                    let dist = radarLoc.distance(from: CLLocation(latitude: pt.latitude,
                                                                   longitude: pt.longitude))
                    if dist < threshold { onRoute = true; break }
                }
                if onRoute { found.insert(radar.id) }
            }
            routeRadars = store.filtered.filter { found.contains($0.id) }
            showConfirmation = true
            suggestions = []
            query = ""

        } catch {
            self.error = "Erreur : \(error.localizedDescription)"
        }
    }

    func clearRoute() {
        route          = nil
        routeRadars    = []
        showConfirmation = false
    }

    // Point le plus proche sur un segment AB depuis P
    private func closestPointOnSegment(
        from p: CLLocationCoordinate2D,
        segA a: CLLocationCoordinate2D,
        segB b: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let dx = b.longitude - a.longitude
        let dy = b.latitude  - a.latitude
        guard dx != 0 || dy != 0 else { return a }
        let t = max(0, min(1,
            ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy)
            / (dx * dx + dy * dy)))
        return CLLocationCoordinate2D(
            latitude:  a.latitude  + t * dy,
            longitude: a.longitude + t * dx)
    }

    // MARK: - Delegate helper
    private final class CompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
        var onResults: ([MKLocalSearchCompletion]) -> Void
        init(_ onResults: @escaping ([MKLocalSearchCompletion]) -> Void) {
            self.onResults = onResults
        }
        func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
            DispatchQueue.main.async { self.onResults(completer.results) }
        }
    }
}

// MARK: - RouteSearchBar

struct RouteSearchBar: View {
    @ObservedObject var vm: RouteViewModel
    @ObservedObject var store: RadarStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Barre de recherche
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 15))
                TextField("Où allez-vous ?", text: $vm.query)
                    .focused($focused)
                    .submitLabel(.search)
                    .onChange(of: vm.query) { vm.search(for: $1) }
                if vm.isSearching {
                    ProgressView().scaleEffect(0.8)
                } else if !vm.query.isEmpty {
                    Button { vm.query = ""; vm.suggestions = [] } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            // Suggestions
            if !vm.suggestions.isEmpty && focused {
                VStack(spacing: 0) {
                    ForEach(vm.suggestions.prefix(6), id: \.self) { sug in
                        Button {
                            focused = false
                            Task { await vm.selectSuggestion(sug, store: store) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.system(size: 18))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sug.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    if !sug.subtitle.isEmpty {
                                        Text(sug.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        Divider().padding(.leading, 44)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                .padding(.top, 6)
            }

            // Erreur
            if let err = vm.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - RouteConfirmationSheet

struct RouteConfirmationSheet: View {
    let route: MKRoute
    let radars: [Radar]
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var radarsByKind: [(kind: RadarKind, count: Int)] {
        let grouped = Dictionary(grouping: radars, by: \.kind)
        return RadarKind.allCases.compactMap { kind in
            let c = grouped[kind]?.count ?? 0
            return c > 0 ? (kind: kind, count: c) : nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Stats itinéraire
                    HStack(spacing: 0) {
                        routeStat(
                            icon: "arrow.triangle.turn.up.right.diamond.fill",
                            value: formatDist(route.distance),
                            label: "Distance",
                            color: .blue
                        )
                        Divider().frame(height: 50)
                        routeStat(
                            icon: "clock.fill",
                            value: formatTime(route.expectedTravelTime),
                            label: "Durée",
                            color: .orange
                        )
                        Divider().frame(height: 50)
                        routeStat(
                            icon: "camera.fill",
                            value: "\(radars.count)",
                            label: "Radars",
                            color: radars.isEmpty ? .green : .red
                        )
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

                    if radars.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text("Trajet sans radar")
                                    .font(.headline)
                                Text("Aucun radar détecté sur cet itinéraire.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        // Radars par type
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Radars sur le trajet")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .kerning(0.5)

                            ForEach(radarsByKind, id: \.kind) { item in
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(item.kind.color.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: item.kind.symbol)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(item.kind.color)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.kind.label)
                                            .font(.system(size: 15, weight: .semibold))
                                        Text(item.kind.modelDescription)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(item.count)")
                                        .font(.system(size: 18, weight: .black, design: .rounded))
                                        .foregroundStyle(item.kind.color)
                                }
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Itinéraire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler", role: .cancel) { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Démarrer") { onConfirm(); dismiss() }
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.regularMaterial)
        .presentationCornerRadius(28)
    }

    private func routeStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDist(_ m: CLLocationDistance) -> String {
        m < 1000 ? String(format: "%.0f m", m)
                 : String(format: "%.0f km", m / 1000)
    }
    private func formatTime(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        return m < 60 ? "\(m) min" : String(format: "%dh%02d", m / 60, m % 60)
    }
}

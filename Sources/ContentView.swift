import MapKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = RadarStore.shared
    @StateObject private var location = LocationService.shared

    @State private var position: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .camera(MapCamera(centerCoordinate: .init(latitude: 48.8566, longitude: 2.3522),
                                    distance: 6000, heading: 20, pitch: 60)))
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selected: Radar?
    @State private var satellite = false
    @State private var showFilters = false

    private let maxPins = 400

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(visibleRadars) { radar in
                Annotation(radar.kind.label, coordinate: radar.coordinate, anchor: .bottom) {
                    RadarPin(kind: radar.kind, highlighted: radar == selected)
                        .onTapGesture { selected = radar }
                }
            }
        }
        .mapStyle(satellite
                  ? .hybrid(elevation: .realistic)
                  : .standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { visibleRegion = $0.region }
        .overlay(alignment: .top) { filterBar }
        .overlay(alignment: .topTrailing) { sideButtons }
        .sheet(item: $selected) { radar in
            RadarDetail(radar: radar)
                .presentationDetents([.height(260)])
                .presentationBackgroundInteraction(.enabled)
        }
        .sheet(isPresented: $showFilters) { FilterSheet(store: store) }
        .task { location.start() }
    }

    /// SwiftUI Map n'a pas de clustering : on n'affiche que les radars de la zone visible, plafonnés.
    private var visibleRadars: [Radar] {
        let all = store.filtered
        guard let r = visibleRegion else { return Array(all.prefix(maxPins)) }
        let inside = all.filter {
            abs($0.coordinate.latitude - r.center.latitude) <= r.span.latitudeDelta / 2 &&
            abs($0.coordinate.longitude - r.center.longitude) <= r.span.longitudeDelta / 2
        }
        if inside.count <= maxPins { return inside }
        let c = CLLocation(latitude: r.center.latitude, longitude: r.center.longitude)
        return Array(inside.sorted { $0.location.distance(from: c) < $1.location.distance(from: c) }.prefix(maxPins))
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RadarKind.allCases) { kind in
                    let on = store.enabledKinds.contains(kind)
                    Button { store.toggle(kind) } label: {
                        Label(kind.label, systemImage: kind.symbol)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? AnyShapeStyle(kind.color) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 6)
        .padding(.trailing, 60)
    }

    private var sideButtons: some View {
        VStack(spacing: 10) {
            roundButton("line.3.horizontal.decrease.circle.fill") { showFilters = true }
            roundButton(satellite ? "map.fill" : "globe.europe.africa.fill") { satellite.toggle() }
        }
        .padding(.top, 52).padding(.trailing, 12)
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3).frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }
}

struct RadarPin: View {
    let kind: RadarKind
    var highlighted = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: kind.symbol)
                .font(.system(size: highlighted ? 18 : 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: highlighted ? 38 : 28, height: highlighted ? 38 : 28)
                .background(kind.color.gradient, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            Image(systemName: "triangle.fill")
                .font(.system(size: 7)).rotationEffect(.degrees(180))
                .foregroundStyle(kind.color).offset(y: -2)
        }
        .animation(.spring(duration: 0.25), value: highlighted)
    }
}

struct RadarDetail: View {
    let radar: Radar

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: radar.kind.symbol).font(.title2).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(radar.kind.color.gradient, in: Circle())
                VStack(alignment: .leading) {
                    Text(radar.kind.label).font(.title3.bold())
                    Text("N° \(radar.id)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack {
                stat("Vitesse max", radar.vmaText)
                Divider().frame(height: 36)
                stat("Mise en service", radar.commissioned?.formatted(date: .abbreviated, time: .omitted) ?? "—")
            }
            Button {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: radar.coordinate))
                item.name = radar.kind.label
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            } label: {
                Label("Itinéraire", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FilterSheet: View {
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Tous") { store.enabledKinds = Set(RadarKind.allCases) }
                    Button("Vitesse uniquement") { store.enabledKinds = RadarKind.speed }
                    Button("Aucun") { store.enabledKinds = [] }
                }
                Section("Types de radars") {
                    ForEach(RadarKind.allCases) { kind in
                        Toggle(isOn: Binding(get: { store.enabledKinds.contains(kind) },
                                             set: { _ in store.toggle(kind) })) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(kind.label)
                                    Text("\(store.count(of: kind)) radars").font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: kind.symbol).foregroundStyle(kind.color)
                            }
                        }
                        .tint(kind.color)
                    }
                }
            }
            .navigationTitle("Filtres")
            .toolbar { Button("OK") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

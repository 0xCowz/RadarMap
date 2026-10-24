import AudioToolbox
import Combine
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Main View

struct ContentView: View {
    @StateObject private var store    = RadarStore.shared
    @StateObject private var location = LocationService.shared
    @StateObject private var alertVM  = RadarAlertViewModel()

    @State private var position: MapCameraPosition = .userLocation(
        followsHeading: true,
        fallback: .camera(MapCamera(
            centerCoordinate: .init(latitude: 48.8566, longitude: 2.3522),
            distance: 8000, heading: 0, pitch: 55)))
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selected: Radar?
    @State private var satellite    = false
    @State private var showFilters  = false
    @State private var showAlert    = false
    @State private var alertRadar: Radar?

    private let maxPins = 300

    var body: some View {
        ZStack {
            // ── Map ──────────────────────────────────────────────────────────
            Map(position: $position) {
                UserAnnotation()
                ForEach(visibleRadars) { radar in
                    Annotation("", coordinate: radar.coordinate, anchor: .bottom) {
                        RadarPin(kind: radar.kind, highlighted: radar == selected)
                            .onTapGesture { withAnimation(.spring(duration: 0.3)) { selected = radar } }
                    }
                }
            }
            .mapStyle(satellite
                      ? .hybrid(elevation: .realistic)
                      : .standard(elevation: .realistic,
                                  emphasis: .muted,
                                  pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapPitchToggle()
            }
            .onMapCameraChange(frequency: .onEnd) { visibleRegion = $0.region }
            .ignoresSafeArea()

            // ── Gradient top ─────────────────────────────────────────────────
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.65), .clear],
                    startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
                .ignoresSafeArea()
                Spacer()
            }

            // ── Gradient bottom ───────────────────────────────────────────────
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .ignoresSafeArea()
            }

            // ── Header ────────────────────────────────────────────────────────
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RadarMap")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(store.filtered.count) radars actifs")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        HeaderButton(symbol: satellite ? "map.fill" : "globe.europe.africa.fill") {
                            satellite.toggle()
                        }
                        HeaderButton(symbol: "line.3.horizontal.decrease.circle.fill") {
                            showFilters = true
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)

                // Filter chips
                filterChips
                    .padding(.top, 14)

                Spacer()

                // Speed strip (bottom)
                speedStrip
                    .padding(.bottom, 30)
            }
        }
        // ── Radar detail sheet ───────────────────────────────────────────────
        .sheet(item: $selected) { radar in
            RadarDetailSheet(radar: radar)
                .presentationDetents([.height(300)])
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(28)
                .presentationBackgroundInteraction(.enabled)
        }
        // ── Filters sheet ────────────────────────────────────────────────────
        .sheet(isPresented: $showFilters) {
            FilterSheet(store: store)
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(28)
        }
        // ── Radar alert banner ───────────────────────────────────────────────
        .overlay(alignment: .top) {
            if showAlert, let r = alertRadar {
                RadarAlertBanner(radar: r, distanceMeters: alertVM.triggeredDistance)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: showAlert)
        .task { location.start() }
        .onReceive(alertVM.$triggeredRadar.compactMap { $0 }) { radar in
            alertRadar = radar
            withAnimation { showAlert = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation { showAlert = false }
            }
        }
        .onAppear { alertVM.start(store: store) }
    }

    // MARK: - Sub views

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RadarKind.allCases) { kind in
                    let on = store.enabledKinds.contains(kind)
                    Button { store.toggle(kind) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 11, weight: .bold))
                            Text(kind.shortLabel)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .foregroundStyle(on ? .white : .white.opacity(0.45))
                        .background {
                            if on {
                                Capsule().fill(kind.color)
                                    .shadow(color: kind.color.opacity(0.5), radius: 6, y: 3)
                            } else {
                                Capsule().fill(.white.opacity(0.1))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(duration: 0.25), value: on)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var speedStrip: some View {
        HStack(spacing: 0) {
            // Nearest radar info
            if let loc = location.location {
                let nearest = store.nearest(to: loc, limit: 1).first
                if let n = nearest {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(n.radar.kind.color.opacity(0.2))
                                .frame(width: 44, height: 44)
                            Image(systemName: n.radar.kind.symbol)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(n.radar.kind.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.radar.kind.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(n.distance < 1000
                                 ? String(format: "%.0f m", n.distance)
                                 : String(format: "%.1f km", n.distance / 1000))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        if let vma = n.radar.vma {
                            SpeedLimitSign(speed: vma)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var visibleRadars: [Radar] {
        let all = store.filtered
        guard let r = visibleRegion else { return Array(all.prefix(maxPins)) }
        let inside = all.filter {
            abs($0.coordinate.latitude - r.center.latitude) <= r.span.latitudeDelta / 2 + 0.01 &&
            abs($0.coordinate.longitude - r.center.longitude) <= r.span.longitudeDelta / 2 + 0.01
        }
        if inside.count <= maxPins { return inside }
        let c = CLLocation(latitude: r.center.latitude, longitude: r.center.longitude)
        return Array(inside.sorted { $0.location.distance(from: c) < $1.location.distance(from: c) }.prefix(maxPins))
    }
}

// MARK: - Header Button

struct HeaderButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.15), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
        }
    }
}

// MARK: - Radar Pin

struct RadarPin: View {
    let kind: RadarKind
    var highlighted = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Glow ring
                Circle()
                    .fill(kind.color.opacity(0.25))
                    .frame(width: highlighted ? 54 : 38, height: highlighted ? 54 : 38)
                // Main circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [kind.color, kind.color.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: highlighted ? 40 : 28, height: highlighted ? 40 : 28)
                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1.5))
                    .shadow(color: kind.color.opacity(0.6), radius: highlighted ? 8 : 4, y: 2)
                Image(systemName: kind.symbol)
                    .font(.system(size: highlighted ? 17 : 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            // Label sous le pin
            Text(kind.shortLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(kind.color.opacity(0.85), in: Capsule())
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            // Pointer
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 5))
                .foregroundStyle(kind.color)
                .offset(y: -2)
        }
        .animation(.spring(duration: 0.3), value: highlighted)
    }
}

// MARK: - Speed Limit Sign

struct SpeedLimitSign: View {
    let speed: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 44, height: 44)
            Circle()
                .stroke(Color.red, lineWidth: 3.5)
                .frame(width: 44, height: 44)
            Text("\(speed)")
                .font(.system(size: speed >= 100 ? 13 : 15, weight: .black, design: .rounded))
                .foregroundStyle(.black)
        }
    }
}

// MARK: - Radar Alert Banner

struct RadarAlertBanner: View {
    let radar: Radar
    var distanceMeters: Double? = nil
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 14) {
            // Icône pulsante
            ZStack {
                Circle()
                    .fill(radar.kind.color.opacity(0.35))
                    .frame(width: 56, height: 56)
                    .scaleEffect(pulse ? 1.5 : 1)
                    .opacity(pulse ? 0 : 0.8)
                Circle()
                    .fill(radar.kind.color)
                    .frame(width: 44, height: 44)
                    .shadow(color: radar.kind.color.opacity(0.5), radius: 8)
                Image(systemName: radar.kind.symbol)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("⚠️ RADAR")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(radar.kind.color)
                        .kerning(1.5)
                    if let d = distanceMeters {
                        Text(d < 1000
                             ? String(format: "· %.0f m", d)
                             : String(format: "· %.1f km", d / 1000))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Text(radar.kind.label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    if let vma = radar.vma {
                        Label("\(vma) km/h", systemImage: "speedometer")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Text("N° \(radar.id)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()

            // Panneau vitesse compact
            if let vma = radar.vma {
                SpeedLimitSign(speed: vma)
                    .scaleEffect(0.85)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(radar.kind.color.opacity(0.6), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
        .padding(.horizontal, 16)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Radar Detail Sheet

struct RadarDetailSheet: View {
    let radar: Radar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 20)

            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(radar.kind.color.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: radar.kind.symbol)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(radar.kind.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(radar.kind.label)
                        .font(.system(size: 20, weight: .bold))
                    Text("Numéro \(radar.id)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let vma = radar.vma {
                    SpeedLimitSign(speed: vma)
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }
            }
            .padding(.horizontal, 20)

            Divider()
                .padding(.vertical, 20)
                .padding(.horizontal, 20)

            HStack(spacing: 0) {
                statCell(
                    icon: "calendar",
                    title: "Mise en service",
                    value: radar.commissioned?.formatted(date: .abbreviated, time: .omitted) ?? "—"
                )
                Divider().frame(height: 40)
                statCell(icon: "speedometer", title: "Limite", value: radar.vmaText)
                Divider().frame(height: 40)
                statCell(icon: "tag.fill", title: "Type", value: radar.kind.rawValue)
            }
            .padding(.horizontal, 20)

            Spacer()

            Button {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: radar.coordinate))
                item.name = radar.kind.label
                item.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                ])
            } label: {
                Label("Itinéraire dans Plans", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(radar.kind.color, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    private func statCell(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold))
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Filter Sheet

struct FilterSheet: View {
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    quickButton("Tous les radars", symbol: "checkmark.circle.fill", color: .blue) {
                        store.enabledKinds = Set(RadarKind.allCases)
                    }
                    quickButton("Vitesse uniquement", symbol: "speedometer", color: .red) {
                        store.enabledKinds = RadarKind.speed
                    }
                    quickButton("Aucun", symbol: "xmark.circle.fill", color: .secondary) {
                        store.enabledKinds = []
                    }
                }
                Section("Types de radars") {
                    ForEach(RadarKind.allCases) { kind in
                        Toggle(isOn: Binding(
                            get: { store.enabledKinds.contains(kind) },
                            set: { _ in store.toggle(kind) }
                        )) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.label).font(.system(size: 15, weight: .semibold))
                                    Text("\(store.count(of: kind)) radars")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(kind.color.opacity(0.15))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: kind.symbol)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(kind.color)
                                }
                            }
                        }
                        .tint(kind.color)
                    }
                }
            }
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func quickButton(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .foregroundStyle(color)
        }
    }
}

// MARK: - RadarKind extension

extension RadarKind {
    var shortLabel: String {
        switch self {
        case .etf:  "Fixe"
        case .etd:  "Discrim."
        case .ett:  "Tourelle"
        case .etu:  "Urbain"
        case .etvm: "Moy."
        case .etfr: "Feu rouge"
        case .etpn: "P.N."
        }
    }
}

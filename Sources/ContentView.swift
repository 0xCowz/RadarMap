import AudioToolbox
import Combine
import CoreLocation
import MapKit
import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var store    = RadarStore.shared
    @StateObject private var location = LocationService.shared
    @StateObject private var alertVM  = RadarAlertViewModel()
    @StateObject private var routeVM  = RouteViewModel()

    @ObservedObject private var audio = AudioAlertService.shared

    @State private var selectedRadar: Radar?
    @State private var route: MKRoute?
    @State private var isNavigating   = false
    @State private var showAlert      = false
    @State private var alertRadar: Radar?
    @State private var showFilters    = false
    @State private var showConfirmation = false
    @State private var showVoiceSetup = !UserDefaults.standard.bool(forKey: "voiceSetupDone")
    @State private var visibleCenter: CLLocationCoordinate2D = .init(latitude: 48.8566, longitude: 2.3522)
    @State private var visibleAltitude: Double = 6000
    @State private var regionTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {

            // ── Carte MapLibre ───────────────────────────────────────────────
            MapLibreView(
                selectedRadar: $selectedRadar,
                route: $route,
                radars: nearbyRadars,
                isNavigating: isNavigating,
                colorScheme: colorScheme,
                onRegionChange: { c, a in
                    // Debounce 250 ms pour éviter les lags
                    regionTask?.cancel()
                    regionTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        if !Task.isCancelled {
                            visibleCenter   = c
                            visibleAltitude = a
                        }
                    }
                }
            )
            .ignoresSafeArea()

            // ── Dégradé haut ────────────────────────────────────────────────
            LinearGradient(
                colors: [Color.black.opacity(0.7), .clear],
                startPoint: .top, endPoint: .bottom)
            .frame(height: 180)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // ── Dégradé bas ─────────────────────────────────────────────────
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.6)],
                    startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // ── UI superposée ────────────────────────────────────────────────
            VStack(spacing: 0) {
                // Entête
                header
                    .padding(.top, 52)

                // Barre de recherche d'itinéraire
                RouteSearchBar(vm: routeVM, store: store)
                    .padding(.top, 10)

                // Chips de filtre
                filterChips
                    .padding(.top, 10)

                Spacer()

                // Bandeau radar proche
                if route == nil {
                    nearestRadarStrip
                        .padding(.bottom, 32)
                }

                // Bouton effacer itinéraire
                if route != nil {
                    clearRouteButton
                        .padding(.bottom, 32)
                }
            }

            // ── Alerte radar ─────────────────────────────────────────────────
            if showAlert, let r = alertRadar {
                RadarAlertBanner(radar: r, distanceMeters: alertVM.triggeredDistance)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(duration: 0.4), value: showAlert)
        // ── Sheets ───────────────────────────────────────────────────────────
        .sheet(item: $selectedRadar) { radar in
            RadarDetailSheet(radar: radar)
                .presentationDetents([.height(360)])
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(28)
                .presentationBackgroundInteraction(.enabled)
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(store: store)
                .presentationDetents([.medium, .large])
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showConfirmation) {
            if let r = routeVM.route {
                RouteConfirmationSheet(
                    route: r,
                    radars: routeVM.routeRadars,
                    onConfirm: { route = routeVM.route; isNavigating = true },
                    onCancel:  { routeVM.clearRoute() }
                )
            }
        }
        .onChange(of: routeVM.showConfirmation) { if $1 { showConfirmation = true } }
        // ── Alertes visuelles ─────────────────────────────────────────────────
        .onReceive(alertVM.$triggeredRadar.compactMap { $0 }) { r in
            alertRadar = r
            withAnimation { showAlert = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation { showAlert = false }
            }
        }
        // ── Alertes vocales ───────────────────────────────────────────────────
        .onReceive(location.$location.compactMap { $0 }) { loc in
            audio.checkProximity(radars: store.filtered, location: loc)
        }
        // ── Setup voix au lancement ───────────────────────────────────────────
        .sheet(isPresented: $showVoiceSetup, onDismiss: {
            UserDefaults.standard.set(true, forKey: "voiceSetupDone")
        }) {
            VoiceSetupView(isPresented: $showVoiceSetup)
                .presentationDetents([.large])
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(28)
                .interactiveDismissDisabled()
        }
        .task { location.start() }
        .onAppear { alertVM.start(store: store) }
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RadarMap")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(store.filtered.count) radars")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            HeaderButton(symbol: "line.3.horizontal.decrease.circle.fill") {
                showFilters = true
            }
        }
        .padding(.horizontal, 20)
    }

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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(on ? .white : .white.opacity(0.45))
                        .background {
                            if on {
                                Capsule().fill(kind.color)
                                    .shadow(color: kind.color.opacity(0.5), radius: 5, y: 2)
                            } else {
                                Capsule().fill(.white.opacity(0.12))
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

    private var nearestRadarStrip: some View {
        Group {
            if let loc = location.location,
               let nearest = store.nearest(to: loc, limit: 1).first {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(nearest.radar.kind.color.opacity(0.18))
                            .frame(width: 48, height: 48)
                        Image(systemName: nearest.radar.kind.symbol)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(nearest.radar.kind.color)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(nearest.radar.kind.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        if !nearest.radar.emplacement.isEmpty {
                            Text(nearest.radar.emplacement)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        if let vma = nearest.radar.vma {
                            SpeedLimitSign(speed: vma)
                        }
                        Text(nearest.distance < 1000
                             ? String(format: "%.0f m", nearest.distance)
                             : String(format: "%.1f km", nearest.distance / 1000))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 16)
            }
        }
    }

    private var clearRouteButton: some View {
        Button {
            routeVM.clearRoute()
            route = nil
            isNavigating = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                Text("Supprimer l'itinéraire")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(Color.red.opacity(0.85), in: Capsule())
            .shadow(color: .red.opacity(0.4), radius: 8, y: 3)
        }
        .padding(.horizontal, 20)
    }

    // Radars visibles en fonction de l'altitude de la caméra
    private var nearbyRadars: [Radar] {
        // Cap selon le niveau de zoom : évite de charger 3350 pins d'un coup
        let maxCount: Int
        switch visibleAltitude {
        case ..<3_000:   maxCount = 150
        case ..<10_000:  maxCount = 80
        case ..<30_000:  maxCount = 40
        case ..<80_000:  maxCount = 20
        default:         return []          // Trop loin, aucun pin
        }
        let radiusDeg = max(0.04, visibleAltitude / 111_000)
        let c = visibleCenter
        return Array(
            store.filtered.filter {
                abs($0.coordinate.latitude  - c.latitude)  <= radiusDeg &&
                abs($0.coordinate.longitude - c.longitude) <= radiusDeg * 1.4
            }.prefix(maxCount)
        )
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

// MARK: - Speed Limit Sign

struct SpeedLimitSign: View {
    let speed: Int
    var body: some View {
        ZStack {
            Circle().fill(.white).frame(width: 40, height: 40)
            Circle().stroke(Color.red, lineWidth: 3).frame(width: 40, height: 40)
            Text("\(speed)")
                .font(.system(size: speed >= 100 ? 12 : 14, weight: .black, design: .rounded))
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
            ZStack {
                Circle()
                    .fill(radar.kind.color.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .scaleEffect(pulse ? 1.5 : 1)
                    .opacity(pulse ? 0 : 0.8)
                Circle()
                    .fill(radar.kind.color)
                    .frame(width: 44, height: 44)
                    .shadow(color: radar.kind.color.opacity(0.5), radius: 8)
                Image(systemName: radar.kind.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("⚠︎ RADAR")
                        .font(.system(size: 11, weight: .black)).kerning(1.5)
                        .foregroundStyle(radar.kind.color)
                    if let d = distanceMeters {
                        Text(d < 1000
                             ? String(format: "· %.0f m", d)
                             : String(format: "· %.1f km", d / 1000))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Text(radar.kind.label)
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                HStack(spacing: 8) {
                    if let vma = radar.vma {
                        Label("\(vma) km/h", systemImage: "speedometer")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                    }
                    if !radar.equipement.brandName.isEmpty, radar.equipement != .other {
                        Text("·  \(radar.equipement.brandName)")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            Spacer()
            if let vma = radar.vma { SpeedLimitSign(speed: vma).scaleEffect(0.8) }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .stroke(radar.kind.color.opacity(0.6), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
        .padding(.horizontal, 16)
        .onAppear {
            withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { pulse = true }
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
                .padding(.top, 12).padding(.bottom, 18)

            // En-tête type + modèle
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(radar.kind.color.opacity(0.15))
                        .frame(width: 58, height: 58)
                    Image(systemName: radar.kind.symbol)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(radar.kind.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(radar.kind.label)
                        .font(.system(size: 19, weight: .bold))
                    HStack(spacing: 6) {
                        if radar.equipement != .other {
                            Text(radar.equipement.brandName)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(radar.kind.color.opacity(0.12),
                                            in: Capsule())
                                .foregroundStyle(radar.kind.color)
                        }
                        Text("N° \(radar.id)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let vma = radar.vma {
                    SpeedLimitSign(speed: vma)
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }
            }
            .padding(.horizontal, 20)

            // Technologie
            if radar.equipement != .other {
                HStack(spacing: 8) {
                    Image(systemName: "cpu.fill").font(.caption).foregroundStyle(.secondary)
                    Text(radar.equipement.technologie)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            Divider().padding(.vertical, 16).padding(.horizontal, 20)

            // Stats
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if !radar.emplacement.isEmpty {
                        statChip(icon: "mappin.circle.fill",
                                 value: radar.emplacement, color: .pink)
                    }
                    if !radar.route.isEmpty {
                        statChip(icon: "road.lanes",
                                 value: radar.route, color: .blue)
                    }
                    if !radar.departement.isEmpty {
                        statChip(icon: "map.fill",
                                 value: "Dép. \(radar.departement)", color: .purple)
                    }
                    if let d = radar.commissioned {
                        statChip(icon: "calendar",
                                 value: d.formatted(date: .abbreviated, time: .omitted),
                                 color: .orange)
                    }
                }
                .padding(.horizontal, 20)
            }

            // Description
            Text(radar.kind.modelDescription)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            if !radar.direction.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(radar.direction)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }

            Spacer()

            // Bouton itinéraire
            Button {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: radar.coordinate))
                item.name = radar.kind.label
                item.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                ])
            } label: {
                Label("Voir dans Plans", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(radar.kind.color, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
    }

    private func statChip(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
            Text(value).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.1), in: Capsule())
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
                    Button {
                        store.enabledKinds = Set(RadarKind.allCases)
                    } label: {
                        Label("Tous les radars", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    Button {
                        store.enabledKinds = RadarKind.speed
                    } label: {
                        Label("Vitesse uniquement", systemImage: "speedometer")
                            .foregroundStyle(.red)
                    }
                    Button {
                        store.enabledKinds = []
                    } label: {
                        Label("Aucun", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
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
                                    Text(kind.label)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("\(store.count(of: kind)) radars")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(kind.color.opacity(0.15))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: kind.symbol)
                                        .font(.system(size: 14, weight: .bold))
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
                    Button("OK") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

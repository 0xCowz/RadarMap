import CoreLocation
import SwiftUI

// MARK: - RadarKind

enum RadarKind: String, CaseIterable, Identifiable, Codable {
    case fixe       = "Radar fixe"
    case discriminant = "Radar discriminant"
    case feuRouge   = "Radar feu rouge"
    case vitMoyenne = "Radar Vitesse Moyenne"
    case pn         = "Radar Passage à Niveau"
    case itineraire = "Itinéraire"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixe:        "Radar fixe"
        case .discriminant:"Radar discriminant"
        case .feuRouge:    "Feu rouge"
        case .vitMoyenne:  "Vitesse moyenne"
        case .pn:          "Passage à niveau"
        case .itineraire:  "Tronçon"
        }
    }

    var shortLabel: String {
        switch self {
        case .fixe:        "Fixe"
        case .discriminant:"Discrim."
        case .feuRouge:    "Feu rouge"
        case .vitMoyenne:  "Moy."
        case .pn:          "P. Niveau"
        case .itineraire:  "Tronçon"
        }
    }

    var symbol: String {
        switch self {
        case .fixe:        "camera.fill"
        case .discriminant:"car.2.fill"
        case .feuRouge:    "exclamationmark.octagon.fill"
        case .vitMoyenne:  "arrow.left.and.right"
        case .pn:          "tram.fill"
        case .itineraire:  "road.lanes"
        }
    }

    var color: Color {
        switch self {
        case .fixe:        Color(red: 0.93, green: 0.18, blue: 0.14)
        case .discriminant:Color(red: 1.00, green: 0.58, blue: 0.00)
        case .feuRouge:    Color(red: 0.20, green: 0.78, blue: 0.35)
        case .vitMoyenne:  Color(red: 0.20, green: 0.50, blue: 1.00)
        case .pn:          Color(red: 0.55, green: 0.27, blue: 0.07)
        case .itineraire:  Color(red: 0.56, green: 0.28, blue: 0.89)
        }
    }

    var modelDescription: String {
        switch self {
        case .fixe:        "Contrôle de vitesse sur une voie"
        case .discriminant:"Contrôle multi-voies avec identification"
        case .feuRouge:    "Contrôle aux feux de signalisation"
        case .vitMoyenne:  "Calcul de vitesse sur un tronçon"
        case .pn:          "Protection passage à niveau"
        case .itineraire:  "Zone de contrôle de vitesse étendue"
        }
    }

    static let speed: Set<RadarKind> = [.fixe, .discriminant, .vitMoyenne, .itineraire]
}

// MARK: - RadarEquipement

enum RadarEquipement: String {
    case morpho   = "MORPHO"
    case parifex  = "PARIFEX"
    case fareco   = "FARECO"
    case aximum   = "AXIMUM"
    case other    = ""

    var brandName: String {
        switch self {
        case .morpho:  "IDEMIA (ex-Morpho)"
        case .parifex: "Parifex"
        case .fareco:  "Fareco"
        case .aximum:  "Aximum"
        case .other:   "Constructeur inconnu"
        }
    }

    var technologie: String {
        switch self {
        case .morpho:  "Capteurs piézoélectriques + flash infrarouge"
        case .parifex: "Laser pulsé"
        case .fareco:  "Boucles inductives"
        case .aximum:  "Radar Doppler"
        case .other:   "—"
        }
    }

    var couleur: Color {
        switch self {
        case .morpho:  Color(red: 0.93, green: 0.18, blue: 0.14)
        case .parifex: Color(red: 0.20, green: 0.50, blue: 1.00)
        case .fareco:  Color(red: 1.00, green: 0.58, blue: 0.00)
        case .aximum:  Color(red: 0.20, green: 0.78, blue: 0.35)
        case .other:   Color.gray
        }
    }
}

// MARK: - Radar

struct Radar: Identifiable, Hashable {
    let id: String
    let kind: RadarKind
    let commissioned: Date?
    let vma: Int?
    let coordinate: CLLocationCoordinate2D
    let equipement: RadarEquipement
    let emplacement: String
    let route: String
    let direction: String
    let departement: String

    static func == (a: Radar, b: Radar) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var location: CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    var vmaText: String { vma.map { "\($0) km/h" } ?? "—" }
    var locationText: String {
        [emplacement, departement].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var routeText: String {
        [route, direction].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    // ── API NAS (mise à jour automatique depuis data.gouv.fr) ────────────────
    static let apiURL = "https://api.lucasmrq.work/api/radars"
    static let reportsURL = "https://api.lucasmrq.work/api/reports"

    /// Charge depuis l'API NAS ; retombe sur le CSV embarqué si hors ligne.
    static func loadAll() async -> [Radar] {
        if let remote = try? await fetchFromAPI() { return remote }
        return loadBundled()
    }

    private static func fetchFromAPI() async throws -> [Radar] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: apiURL)!)
        let json = try JSONDecoder().decode(APIResponse.self, from: data)
        return json.radars.compactMap { Radar(from: $0) }
    }

    // Structure JSON reçue de l'API
    private struct APIResponse: Decodable {
        let radars: [APIRadar]
    }
    struct APIRadar: Decodable {
        let id, type: String
        let date: String?
        let vma: Int?
        let lat, lon: Double
        let equipement, emplacement, route, direction, departement: String
    }

    init?(from r: APIRadar) {
        guard let kind = RadarKind(rawValue: r.type) else { return nil }
        let isoFmt = ISO8601DateFormatter()
        self.id          = r.id
        self.kind        = kind
        self.commissioned = r.date.flatMap { isoFmt.date(from: $0) }
        self.vma         = r.vma
        self.coordinate  = CLLocationCoordinate2D(latitude: r.lat, longitude: r.lon)
        self.equipement  = RadarEquipement(rawValue: r.equipement.uppercased()) ?? .other
        self.emplacement = r.emplacement
        self.route       = r.route
        self.direction   = r.direction
        self.departement = r.departement
    }

    // ── CSV embarqué (fallback hors ligne) ───────────────────────────────────
    // Colonnes data.gouv.fr (virgule) :
    // 0=date_maj 1=date_creation 2=dept 3=lat 4=lon 5=id 6=direction
    // 7=equipement 8=date_install 9=type 10=emplacement 11=route 12=longueur
    // 13=vma_pl 14=vma_vl
    static func loadBundled() -> [Radar] {
        guard let url = Bundle.main.url(forResource: "radars", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let isoFmt = ISO8601DateFormatter()
        return text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line -> Radar? in
            let c = String(line).components(separatedBy: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count >= 6,
                  let kind = RadarKind(rawValue: c[1]),
                  let lat  = Double(c[4]),
                  let lon  = Double(c[5]) else { return nil }
            return Radar(
                id: c[0], kind: kind,
                commissioned: isoFmt.date(from: c[2]), vma: Int(c[3]),
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                equipement: c.count > 6 ? RadarEquipement(rawValue: c[6]) ?? .other : .other,
                emplacement: c.count > 7 ? c[7] : "",
                route:       c.count > 8 ? c[8] : "",
                direction:   c.count > 9 ? c[9] : "",
                departement: c.count > 10 ? c[10] : ""
            )
        }
    }
}

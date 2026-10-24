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

    // Colonnes: id;type;date;vma;lat;lon;equipement;emplacement;route;direction;departement
    static func loadBundled() -> [Radar] {
        guard let url = Bundle.main.url(forResource: "radars", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

        return text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let c = line.split(separator: ";", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count >= 6,
                  let kind = RadarKind(rawValue: c[1]),
                  let lat  = Double(c[4]),
                  let lon  = Double(c[5]) else { return nil }

            let vma = Int(c[3])
            let date = isoFmt.date(from: c[2])
            let equip = c.count > 6 ? RadarEquipement(rawValue: c[6]) ?? .other : .other
            let empl  = c.count > 7 ? c[7] : ""
            let route = c.count > 8 ? c[8] : ""
            let direc = c.count > 9 ? c[9] : ""
            let dept  = c.count > 10 ? c[10] : ""

            return Radar(
                id: c[0], kind: kind, commissioned: date, vma: vma,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                equipement: equip, emplacement: empl, route: route,
                direction: direc, departement: dept
            )
        }
    }
}

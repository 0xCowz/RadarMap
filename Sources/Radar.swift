import CoreLocation
import SwiftUI

enum RadarKind: String, CaseIterable, Identifiable, Codable {
    case etf = "ETF", etd = "ETD", ett = "ETT", etu = "ETU", etvm = "ETVM", etfr = "ETFR", etpn = "ETPN"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .etf: "Radar fixe"
        case .etd: "Radar discriminant"
        case .ett: "Radar tourelle"
        case .etu: "Radar urbain"
        case .etvm: "Vitesse moyenne"
        case .etfr: "Feu rouge"
        case .etpn: "Passage à niveau"
        }
    }

    var symbol: String {
        switch self {
        case .etf: "speedometer"
        case .etd: "car.2.fill"
        case .ett: "camera.fill"
        case .etu: "building.2.fill"
        case .etvm: "arrow.left.and.right"
        case .etfr: "exclamationmark.octagon.fill"
        case .etpn: "tram.fill"
        }
    }

    var color: Color {
        switch self {
        case .etf: .red
        case .etd: .orange
        case .ett: .purple
        case .etu: .pink
        case .etvm: .blue
        case .etfr: .green
        case .etpn: .brown
        }
    }

    /// Radars de contrôle de vitesse (par opposition aux feux et passages à niveau).
    static let speed: Set<RadarKind> = [.etf, .etd, .ett, .etu, .etvm]
}

struct Radar: Identifiable, Hashable {
    let id: String
    let kind: RadarKind
    let commissioned: Date?
    let vma: Int?
    let coordinate: CLLocationCoordinate2D

    static func == (a: Radar, b: Radar) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var location: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }
    var vmaText: String { vma.map { "\($0) km/h" } ?? "—" }

    /// Colonnes : numéro;type;date;VMA;latitude;longitude
    static func loadBundled() -> [Radar] {
        guard let url = Bundle.main.url(forResource: "radars", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "dd/MM/yyyy HH:mm"
        return text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let c = line.split(separator: ";", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count >= 6, let kind = RadarKind(rawValue: c[1]),
                  let lat = Double(c[4].replacingOccurrences(of: "+", with: "")),
                  let lon = Double(c[5].replacingOccurrences(of: "+", with: "")) else { return nil }
            return Radar(id: c[0], kind: kind, commissioned: fmt.date(from: c[2]), vma: Int(c[3]),
                         coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }
}

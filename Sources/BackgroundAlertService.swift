import Combine
import CoreLocation
import Foundation
import UIKit
import UserNotifications

// MARK: - BackgroundAlertService
//
// Runs continuously (foreground + background).
// • Audio alerts  → AudioAlertService (ducked over Waze on CarPlay)
// • Local notifs  → fired only when app is not in foreground (screen locked, etc.)
// • Live Activity → always updated

final class BackgroundAlertService: NSObject {
    static let shared = BackgroundAlertService()

    private var cancellable: AnyCancellable?
    private var notifiedKeys: Set<String> = []
    private var prevDist:     [String: CLLocationDistance] = [:]

    // MARK: - Start

    func start() {
        requestNotificationPermission()

        cancellable = LocationService.shared.$location
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in self?.handle(loc) }
    }

    // MARK: - Core handler

    private func handle(_ location: CLLocation) {
        let radars    = RadarStore.shared.filtered
        let appActive = UIApplication.shared.applicationState == .active

        if !appActive {
            // Audio (AVSpeechSynthesizer ducke Waze)
            AudioAlertService.shared.checkProximity(radars: radars, location: location)
            // Notifications locales (écran verrouillé)
            checkAndNotify(radars: radars, location: location)
        }

        // Live Activity : toujours mis à jour
        LiveActivityManager.shared.update(location: location, radars: radars)
    }

    // MARK: - Local notifications

    private func checkAndNotify(radars: [Radar], location: CLLocation) {
        let course = location.course

        for radar in radars {
            let dist     = location.distance(from: radar.location)
            let previous = prevDist[radar.id] ?? .infinity
            prevDist[radar.id] = dist

            // Approche seulement
            guard dist < previous - 25 else { continue }

            // Tiers 600 m / 300 m / 100 m
            let tier: String
            switch dist {
            case ..<110:  tier = "veryclose"
            case ..<320:  tier = "close"
            case ..<620:  tier = "far"
            default:      continue
            }

            let key = "\(radar.id)-\(tier)"
            guard !notifiedKeys.contains(key) else { continue }

            // Cône ±45°
            if course >= 0 {
                let bearing = location.bearing(to: radar.coordinate)
                guard abs(angleDiff(course, bearing)) < 45 else { continue }
            } else if radar.kind == .feuRouge || radar.kind == .pn {
                continue  // Radar ponctuel urbain : cap obligatoire
            }

            // Marquer le tier courant ET les plus lointains
            notifiedKeys.insert(key)
            if tier == "veryclose" {
                notifiedKeys.insert("\(radar.id)-close")
                notifiedKeys.insert("\(radar.id)-far")
            } else if tier == "close" {
                notifiedKeys.insert("\(radar.id)-far")
            }

            post(for: radar, distanceMeters: Int(dist), tier: tier)
        }

        // Libérer clés au-delà de 1 km
        let nearbyIds = Set(radars.filter { location.distance(from: $0.location) < 1_000 }.map(\.id))
        notifiedKeys = notifiedKeys.filter { nearbyIds.contains(idFromKey($0)) }
        let allIds = Set(radars.map(\.id))
        prevDist   = prevDist.filter { allIds.contains($0.key) }
    }

    private func post(for radar: Radar, distanceMeters: Int, tier: String) {
        let content = UNMutableNotificationContent()
        content.title = radar.kind.label

        let rounded = max((distanceMeters / 50) * 50, 50)
        let distStr = rounded < 1_000
            ? "\(rounded) m"
            : String(format: "%.1f km", Double(rounded) / 1_000)

        switch tier {
        case "veryclose": content.body = "⚠️ \(distStr) — ralentissez !"
        case "close":     content.body = "Radar dans \(distStr)"
        default:          content.body = "Radar signalé dans \(distStr)"
        }

        if let vma = radar.vma { content.subtitle = "Limite : \(vma) km/h" }
        content.sound             = .default
        content.interruptionLevel = .timeSensitive

        let req = UNNotificationRequest(
            identifier: "radar-\(radar.id)-\(tier)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    // MARK: - Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    // MARK: - Helpers

    private func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = b - a
        while d >  180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    private func idFromKey(_ key: String) -> String {
        key.components(separatedBy: "-").dropLast().joined(separator: "-")
    }
}

// MARK: - CLLocation bearing

extension CLLocation {
    func bearing(to coord: CLLocationCoordinate2D) -> Double {
        let lat1 = coordinate.latitude  * .pi / 180
        let lat2 = coord.latitude       * .pi / 180
        let dLon = (coord.longitude - coordinate.longitude) * .pi / 180
        let y    = sin(dLon) * cos(lat2)
        let x    = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

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
    // Keys already notified ("radarId-far", "radarId-close") — reset when radar leaves zone
    private var notifiedKeys: Set<String> = []

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
        let radars = RadarStore.shared.filtered
        let appActive = UIApplication.shared.applicationState == .active

        // Audio alerts run in bg via .playback + .duckOthers — always process
        if !appActive {
            AudioAlertService.shared.checkProximity(radars: radars, location: location)
        }
        // (When active, ContentView's onReceive handles it — no double-call)

        // Local push notifications when screen is off / app backgrounded
        if !appActive {
            checkAndNotify(radars: radars, location: location)
        }

        // Live Activity — always up-to-date
        LiveActivityManager.shared.update(location: location, radars: radars)
    }

    // MARK: - Local notifications

    private func checkAndNotify(radars: [Radar], location: CLLocation) {
        let course = location.course

        for radar in radars {
            let dist = location.distance(from: radar.location)

            let tier: String
            switch dist {
            case ..<220:  tier = "close"
            case ..<520:  tier = "far"
            default:      continue
            }

            let key = "\(radar.id)-\(tier)"
            guard !notifiedKeys.contains(key) else { continue }

            // Bearing check (skip if heading away)
            if course >= 0 {
                let bearing = location.bearing(to: radar.coordinate)
                guard abs(angleDiff(course, bearing)) < 70 else { continue }
            }

            notifiedKeys.insert(key)
            post(for: radar, distanceMeters: Int(dist), tier: tier)
        }

        // Clean up keys for radars now far away
        let nearbyIds = Set(
            radars.filter { location.distance(from: $0.location) < 700 }.map(\.id)
        )
        notifiedKeys = notifiedKeys.filter { key in
            let id = key.split(separator: "-").dropLast().joined(separator: "-")
            return nearbyIds.contains(id)
        }
    }

    private func post(for radar: Radar, distanceMeters: Int, tier: String) {
        let content        = UNMutableNotificationContent()
        content.title      = radar.kind.label
        content.categoryIdentifier = "RADAR"

        let rounded = (distanceMeters / 50) * 50   // arrondi 50 m
        let distStr = rounded < 1_000
            ? "\(max(rounded, 50)) m"
            : String(format: "%.1f km", Double(rounded) / 1_000)

        content.body = tier == "close"
            ? "⚠️ À \(distStr) — ralentissez !"
            : "Radar dans \(distStr)"

        if let vma = radar.vma {
            content.subtitle = "Limite : \(vma) km/h"
        }
        content.sound             = .default
        content.interruptionLevel = .timeSensitive

        let req = UNNotificationRequest(
            identifier: "radar-\(radar.id)-\(tier)",
            content: content,
            trigger: nil   // immediate
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
}

// MARK: - CLLocation bearing (internal — used by BackgroundAlertService + AudioAlertService)

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

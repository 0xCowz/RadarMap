import ActivityKit
import CoreLocation
import Foundation

// MARK: - LiveActivityManager

final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<RadarActivityAttributes>?
    private var routeDestination: String?
    private var radarsOnRoute: Int = 0

    // MARK: - Lifecycle

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return }

        let state = idleState()
        let attrs = RadarActivityAttributes()

        do {
            activity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Live Activities unavailable (simulator, older OS, etc.)
        }
    }

    func stop() {
        Task {
            await activity?.end(.init(state: idleState(), staleDate: nil),
                                dismissalPolicy: .immediate)
            activity = nil
        }
    }

    // MARK: - Route context (set from RouteViewModel)

    func setRoute(destination: String?, radarCount: Int) {
        routeDestination = destination
        radarsOnRoute    = radarCount
    }

    // MARK: - Update on location change

    func update(location: CLLocation, radars: [Radar]) {
        guard let activity else { return }

        let nearest = radars
            .map { (radar: $0, dist: location.distance(from: $0.location)) }
            .filter { $0.dist < 1_000 }
            .min { $0.dist < $1.dist }

        let state: RadarActivityAttributes.ContentState
        if let hit = nearest {
            let d    = Int(hit.dist)
            let text = d < 1_000 ? "\(d) m" : String(format: "%.1f km", Double(d) / 1_000)
            state = makeState(hit.radar, distanceText: text)
        } else {
            state = idleState()
        }

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - State builders

    private func idleState() -> RadarActivityAttributes.ContentState {
        .init(
            hasRadarAhead:    false,
            radarSymbol:      "checkmark.circle.fill",
            radarLabel:       "Aucun radar",
            distanceText:     "—",
            speedLimit:       nil,
            colorR: 0.20, colorG: 0.78, colorB: 0.35,
            routeDestination: routeDestination,
            radarsOnRoute:    radarsOnRoute
        )
    }

    private func makeState(_ radar: Radar, distanceText: String) -> RadarActivityAttributes.ContentState {
        let (r, g, b) = colorComponents(for: radar.kind)
        return .init(
            hasRadarAhead:    true,
            radarSymbol:      radar.kind.symbol,
            radarLabel:       radar.kind.label,
            distanceText:     distanceText,
            speedLimit:       radar.vma,
            colorR: r, colorG: g, colorB: b,
            routeDestination: routeDestination,
            radarsOnRoute:    radarsOnRoute
        )
    }

    private func colorComponents(for kind: RadarKind) -> (Double, Double, Double) {
        switch kind {
        case .fixe:        return (0.93, 0.18, 0.14)
        case .discriminant:return (1.00, 0.58, 0.00)
        case .feuRouge:    return (0.20, 0.78, 0.35)
        case .vitMoyenne:  return (0.20, 0.50, 1.00)
        case .pn:          return (0.55, 0.27, 0.07)
        case .itineraire:  return (0.56, 0.28, 0.89)
        }
    }
}

import ActivityKit
import Foundation

struct RadarActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var hasRadarAhead: Bool
        var radarSymbol: String   // SF Symbol
        var radarLabel: String    // "Radar fixe"
        var distanceText: String  // "300 m"
        var speedLimit: Int?
        // Color components (avoids a custom Codable type)
        var colorR: Double
        var colorG: Double
        var colorB: Double
        // Route context (nil if no active route)
        var routeDestination: String?
        var radarsOnRoute: Int
    }
    var placeholder: String = "Radars"
}

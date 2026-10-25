import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget entry point

struct RadarLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RadarActivityAttributes.self) { context in
            LockScreenLiveActivityView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(state: context.state)
                }
            } compactLeading: {
                CompactLeadingView(state: context.state)
            } compactTrailing: {
                CompactTrailingView(state: context.state)
            } minimal: {
                MinimalView(state: context.state)
            }
        }
    }
}

// MARK: - Lock Screen view

private struct LockScreenLiveActivityView: View {
    let state: RadarActivityAttributes.ContentState

    var radarColor: Color { Color(red: state.colorR, green: state.colorG, blue: state.colorB) }

    var body: some View {
        HStack(spacing: 14) {
            // ── Left icon ────────────────────────────────────────────
            ZStack {
                Circle()
                    .fill(radarColor.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: state.radarSymbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(state.hasRadarAhead ? radarColor : .green)
            }

            // ── Center info ───────────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                Text(state.radarLabel)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    if state.hasRadarAhead {
                        Text("dans \(state.distanceText)")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                    } else {
                        Text("Aucun radar détecté")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.60))
                    }
                }

                if let dest = state.routeDestination {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.50))
                        Text(dest)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                        if state.radarsOnRoute > 0 {
                            Text("· \(state.radarsOnRoute) radar\(state.radarsOnRoute > 1 ? "s" : "")")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.40))
                        }
                    }
                }
            }

            Spacer()

            // ── Speed badge ───────────────────────────────────────────
            if let vma = state.speedLimit {
                SpeedBadgeView(speed: vma)
            } else if !state.hasRadarAhead {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.green.opacity(0.85))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Speed badge (panneau routier)

private struct SpeedBadgeView: View {
    let speed: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 44, height: 44)
            Circle()
                .strokeBorder(.red, lineWidth: 3.5)
                .frame(width: 44, height: 44)
            Text("\(speed)")
                .font(.system(size: speed >= 100 ? 13 : 16, weight: .black, design: .rounded))
                .foregroundStyle(.black)
        }
    }
}

// MARK: - Dynamic Island expanded regions

private struct ExpandedLeadingView: View {
    let state: RadarActivityAttributes.ContentState
    var radarColor: Color { Color(red: state.colorR, green: state.colorG, blue: state.colorB) }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(radarColor.opacity(0.20))
                    .frame(width: 36, height: 36)
                Image(systemName: state.radarSymbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(state.hasRadarAhead ? radarColor : .green)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(state.radarLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.hasRadarAhead ? "dans \(state.distanceText)" : "Tout est OK")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
    }
}

private struct ExpandedTrailingView: View {
    let state: RadarActivityAttributes.ContentState

    var body: some View {
        if let vma = state.speedLimit {
            SpeedBadgeView(speed: vma)
                .padding(.trailing, 4)
        }
    }
}

private struct ExpandedBottomView: View {
    let state: RadarActivityAttributes.ContentState

    var body: some View {
        if let dest = state.routeDestination {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Vers \(dest)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if state.radarsOnRoute > 0 {
                    Text("\(state.radarsOnRoute) radar\(state.radarsOnRoute > 1 ? "s" : "") sur le trajet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Dynamic Island compact / minimal

private struct CompactLeadingView: View {
    let state: RadarActivityAttributes.ContentState
    var radarColor: Color { Color(red: state.colorR, green: state.colorG, blue: state.colorB) }

    var body: some View {
        Image(systemName: state.hasRadarAhead ? state.radarSymbol : "checkmark.circle.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(state.hasRadarAhead ? radarColor : .green)
            .padding(.leading, 4)
    }
}

private struct CompactTrailingView: View {
    let state: RadarActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.hasRadarAhead {
                Text(state.distanceText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Text("OK")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.trailing, 4)
    }
}

private struct MinimalView: View {
    let state: RadarActivityAttributes.ContentState
    var radarColor: Color { Color(red: state.colorR, green: state.colorG, blue: state.colorB) }

    var body: some View {
        Image(systemName: state.hasRadarAhead ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(state.hasRadarAhead ? radarColor : .green)
    }
}

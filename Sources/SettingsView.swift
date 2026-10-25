import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            List {

                // ── Source des données ────────────────────────────────────────
                Section("Source des données") {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(store.dataSource == "API NAS" ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                .frame(width: 38, height: 38)
                            Image(systemName: store.dataSource == "API NAS" ? "cloud.fill" : "doc.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(store.dataSource == "API NAS" ? .green : .orange)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.dataSource)
                                .font(.system(size: 15, weight: .semibold))
                            Text(store.dataSource == "API NAS"
                                 ? "api.lucasmrq.work · data.gouv.fr"
                                 : "Données embarquées dans l'app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.isLoadingRemote {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 18))
                        }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Label("Dernière mise à jour", systemImage: "clock.fill")
                            .font(.system(size: 14))
                        Spacer()
                        Text(store.lastUpdated.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await store.refreshFromAPI() }
                    } label: {
                        HStack {
                            Label("Forcer la mise à jour", systemImage: "arrow.clockwise")
                                .foregroundStyle(.blue)
                            Spacer()
                            if store.isLoadingRemote {
                                ProgressView().scaleEffect(0.75)
                            }
                        }
                    }
                    .disabled(store.isLoadingRemote)
                }

                // ── Statistiques radars ───────────────────────────────────────
                Section("Radars chargés (\(store.all.count) au total)") {
                    ForEach(RadarKind.allCases) { kind in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(kind.color.opacity(0.12))
                                    .frame(width: 32, height: 32)
                                Image(systemName: kind.symbol)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(kind.color)
                            }
                            Text(kind.label)
                                .font(.system(size: 14))
                            Spacer()
                            Text("\(store.count(of: kind))")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                // ── Application ──────────────────────────────────────────────
                Section("Application") {
                    HStack {
                        Label("Version", systemImage: "app.fill")
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Données radars", systemImage: "location.fill")
                        Spacer()
                        Text("data.gouv.fr")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Cartographie", systemImage: "map.fill")
                        Spacer()
                        Text("OpenFreeMap · MapLibre")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Paramètres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

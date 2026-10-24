import CarPlay
import Combine
import CoreLocation
import SwiftUI

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CPInterfaceController?
    private var tabBar: CPTabBarTemplate?
    private var bag = Set<AnyCancellable>()
    private let store = RadarStore.shared
    private let fallback = CLLocation(latitude: 48.8566, longitude: 2.3522)

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        controller = interfaceController
        LocationService.shared.start()
        rebuild()

        LocationService.shared.$location
            .throttle(for: 10, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &bag)

        store.$enabledKinds.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &bag)
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        controller = nil
        tabBar     = nil
        bag.removeAll()
    }

    private func rebuild() {
        let nearby  = CPListTemplate(title: "À proximité", sections: [nearbySection()])
        nearby.tabTitle = "Proches"
        nearby.tabImage = UIImage(systemName: "location.fill")

        let filters = CPListTemplate(title: "Filtres", sections: [filterSection()])
        filters.tabTitle = "Filtres"
        filters.tabImage = UIImage(systemName: "line.3.horizontal.decrease.circle")

        if let tabBar {
            tabBar.updateTemplates([nearby, filters])
        } else {
            let t = CPTabBarTemplate(templates: [nearby, filters])
            tabBar = t
            controller?.setRootTemplate(t, animated: false, completion: nil)
        }
    }

    private func nearbySection() -> CPListSection {
        let here  = LocationService.shared.location ?? fallback
        let items = store.nearest(to: here, limit: 12).map { entry -> CPListItem in
            let km   = entry.distance / 1000
            let dist = km < 10 ? String(format: "%.1f km", km) : String(format: "%.0f km", km)
            var detail = "Limite : \(entry.radar.vmaText)"
            if !entry.radar.emplacement.isEmpty { detail += " · \(entry.radar.emplacement)" }
            return CPListItem(
                text: "\(entry.radar.kind.label) · \(dist)",
                detailText: detail,
                image: Self.icon(entry.radar.kind))
        }
        return CPListSection(items: items)
    }

    private func filterSection() -> CPListSection {
        let items = RadarKind.allCases.map { kind -> CPListItem in
            let on   = store.enabledKinds.contains(kind)
            let item = CPListItem(
                text: kind.label,
                detailText: on ? "Affiché ✓" : "Masqué",
                image: Self.icon(kind, dimmed: !on))
            item.handler = { [weak self] _, completion in
                self?.store.toggle(kind)
                completion()
            }
            return item
        }
        return CPListSection(items: items)
    }

    private static func icon(_ kind: RadarKind, dimmed: Bool = false) -> UIImage? {
        let cfg   = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        let color = UIColor(kind.color).withAlphaComponent(dimmed ? 0.3 : 1)
        return UIImage(systemName: kind.symbol, withConfiguration: cfg)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
    }
}

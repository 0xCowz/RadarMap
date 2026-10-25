import MapLibre
import MapKit
import SwiftUI
import UIKit

// MARK: - MapLibreView

struct MapLibreView: UIViewRepresentable {
    @Binding var selectedRadar: Radar?
    @Binding var route: MKRoute?
    var radars: [Radar]
    var isNavigating: Bool = false
    var colorScheme: ColorScheme = .light
    var onRegionChange: ((CLLocationCoordinate2D, Double) -> Void)?

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = URL(string: "https://tiles.openfreemap.org/styles/bright")!
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow   // Démarre centré sur l'utilisateur
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.logoView.isHidden = false
        mapView.attributionButton.isHidden = false
        mapView.compassView.compassVisibility = .adaptive
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        // Mode navigation : suit la voiture avec cap
        if !isNavigating {
            context.coordinator.cancelRecenter()
        }
        if isNavigating && !context.coordinator.userIsPanning
            && mapView.userTrackingMode != .followWithCourse {
            mapView.userTrackingMode = .followWithCourse
            let center = mapView.userLocation?.coordinate ?? mapView.centerCoordinate
            let cam = MLNMapCamera(
                lookingAtCenter: center,
                altitude: 500, pitch: 60, heading: mapView.camera.heading)
            mapView.setCamera(cam, withDuration: 0.8, animationTimingFunction: nil)
        }

        // Dark / light mode – applique seulement si le schéma change
        context.coordinator.applySchemeIfNeeded(colorScheme, on: mapView)

        context.coordinator.updateRadarAnnotations(on: mapView, radars: radars, selected: selectedRadar)
        context.coordinator.updateRoute(on: mapView, route: route)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreView
        private var styleLoaded = false
        private var pendingRadars: [Radar]?
        private var pendingSelected: Radar?
        private var pendingRoute: MKRoute?
        var currentScheme: ColorScheme = .light

        // Pan libre + recenter 5s
        private var recenterTimer: Timer?
        var userIsPanning = false

        init(_ parent: MapLibreView) { self.parent = parent }

        // ── Style chargé ─────────────────────────────────────────────────────
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleLoaded = true
            apply3DBuildings(to: style)
            applyAppearance(to: style, dark: currentScheme == .dark)
            if let r = pendingRadars {
                updateRadarAnnotations(on: mapView, radars: r, selected: pendingSelected)
                pendingRadars = nil
            }
            if let r = pendingRoute {
                updateRoute(on: mapView, route: r)
                pendingRoute = nil
            }
        }

        // ── Dark / Light switch ───────────────────────────────────────────────
        func applySchemeIfNeeded(_ scheme: ColorScheme, on mapView: MLNMapView) {
            guard scheme != currentScheme else { return }
            currentScheme = scheme
            guard let style = mapView.style, styleLoaded else { return }
            applyAppearance(to: style, dark: scheme == .dark)
        }

        // ── Bâtiments 3D ─────────────────────────────────────────────────────
        private func apply3DBuildings(to style: MLNStyle) {
            guard let source = style.source(withIdentifier: "openmaptiles") else { return }
            if let old = style.layer(withIdentifier: "building") { style.removeLayer(old) }
            let ext = MLNFillExtrusionStyleLayer(identifier: "3d-buildings", source: source)
            ext.sourceLayerIdentifier = "building"
            ext.predicate = NSPredicate(format: "render_height >= 0")
            ext.fillExtrusionBase   = NSExpression(forKeyPath: "render_min_height")
            ext.fillExtrusionHeight = NSExpression(forKeyPath: "render_height")
            ext.fillExtrusionColor  = NSExpression(forConstantValue:
                UIColor(red: 0.90, green: 0.91, blue: 0.95, alpha: 1))
            ext.fillExtrusionOpacity = NSExpression(forConstantValue: 0.65)
            style.addLayer(ext)
        }

        // ── Apparence carte (light / dark) ────────────────────────────────────
        private func applyAppearance(to style: MLNStyle, dark: Bool) {
            guard dark else { return }   // Light : le style bright est déjà bien, on ne touche à rien

            // Dark mode uniquement : teinter les calques principaux
            if let bg = style.layer(withIdentifier: "background") as? MLNBackgroundStyleLayer {
                bg.backgroundColor = NSExpression(forConstantValue:
                    UIColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1))
            }
            let darkLand = UIColor(red: 0.11, green: 0.12, blue: 0.17, alpha: 1)
            for id in style.layers.compactMap({ $0 as? MLNFillStyleLayer }).map(\.identifier)
                where id.hasPrefix("landuse") || id.hasPrefix("landcover") || id == "land" {
                if let l = style.layer(withIdentifier: id) as? MLNFillStyleLayer {
                    l.fillColor = NSExpression(forConstantValue: darkLand)
                }
            }
            if let w = style.layer(withIdentifier: "water") as? MLNFillStyleLayer {
                w.fillColor = NSExpression(forConstantValue:
                    UIColor(red: 0.06, green: 0.14, blue: 0.28, alpha: 1))
            }
            let darkRoad = UIColor(red: 0.20, green: 0.22, blue: 0.30, alpha: 1)
            for l in style.layers.compactMap({ $0 as? MLNLineStyleLayer })
                where l.identifier.hasPrefix("road") || l.identifier.hasPrefix("highway") || l.identifier.hasPrefix("tunnel") {
                l.lineColor = NSExpression(forConstantValue: darkRoad)
            }
            for l in style.layers.compactMap({ $0 as? MLNFillStyleLayer })
                where l.identifier.hasPrefix("road") || l.identifier.hasPrefix("tunnel") {
                l.fillColor = NSExpression(forConstantValue: darkRoad)
            }
        }

        // ── Annotations radar ─────────────────────────────────────────────────
        func updateRadarAnnotations(on mapView: MLNMapView, radars: [Radar], selected: Radar?) {
            guard styleLoaded else {
                pendingRadars = radars; pendingSelected = selected; return
            }
            if let existing = mapView.annotations?.compactMap({ $0 as? RadarMapAnnotation }) {
                mapView.removeAnnotations(existing)
            }
            let annotations = radars.map { radar -> RadarMapAnnotation in
                let ann = RadarMapAnnotation()
                ann.radar      = radar
                ann.coordinate = radar.coordinate
                ann.title      = radar.kind.label
                ann.subtitle   = radar.vmaText
                return ann
            }
            if !annotations.isEmpty { mapView.addAnnotations(annotations) }
        }

        // ── Itinéraire ────────────────────────────────────────────────────────
        func updateRoute(on mapView: MLNMapView, route: MKRoute?) {
            guard styleLoaded else { pendingRoute = route; return }
            if let s = mapView.style {
                ["route-casing", "route-line"].forEach { id in
                    if let l = s.layer(withIdentifier: id) { s.removeLayer(l) }
                }
                if let src = s.source(withIdentifier: "route-source") { s.removeSource(src) }
            }
            guard let route, let style = mapView.style else { return }

            var coords = route.polyline.coordinates
            let polyline = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
            let source = MLNShapeSource(identifier: "route-source", features: [polyline], options: nil)
            style.addSource(source)

            let casing = MLNLineStyleLayer(identifier: "route-casing", source: source)
            casing.lineColor   = NSExpression(forConstantValue: UIColor.white)
            casing.lineWidth   = NSExpression(forConstantValue: 9)
            casing.lineCap     = NSExpression(forConstantValue: "round")
            casing.lineJoin    = NSExpression(forConstantValue: "round")
            style.addLayer(casing)

            let line = MLNLineStyleLayer(identifier: "route-line", source: source)
            line.lineColor = NSExpression(forConstantValue:
                UIColor(red: 0.12, green: 0.47, blue: 1.0, alpha: 1))
            line.lineWidth = NSExpression(forConstantValue: 6)
            line.lineCap   = NSExpression(forConstantValue: "round")
            line.lineJoin  = NSExpression(forConstantValue: "round")
            style.addLayer(line)
        }

        // ── Vues d'annotation ─────────────────────────────────────────────────
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let ann = annotation as? RadarMapAnnotation,
                  let radar = ann.radar else { return nil }
            let id = "pin-\(radar.kind.rawValue)"
            let selected = radar == parent.selectedRadar
            if let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? RadarPinView {
                v.configure(kind: radar.kind, vma: radar.vma, selected: selected)
                return v
            }
            let v = RadarPinView(reuseIdentifier: id)
            v.configure(kind: radar.kind, vma: radar.vma, selected: selected)
            return v
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard let ann = annotation as? RadarMapAnnotation, let r = ann.radar else { return }
            DispatchQueue.main.async { self.parent.selectedRadar = r }
        }

        func mapView(_ mapView: MLNMapView, didDeselect annotation: MLNAnnotation) {}

        func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason,
                     animated: Bool) {
            let gestures: MLNCameraChangeReason = [.gesturePan, .gesturePinch,
                                                    .gestureRotate, .gestureTilt]
            guard !reason.intersection(gestures).isEmpty else { return }
            // L'utilisateur déplace la carte manuellement
            if parent.isNavigating && !userIsPanning {
                userIsPanning = true
                mapView.userTrackingMode = .none
            }
            scheduleRecenter(mapView)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason,
                     animated: Bool) {
            parent.onRegionChange?(mapView.centerCoordinate, mapView.camera.altitude)
        }

        func cancelRecenter() {
            recenterTimer?.invalidate()
            recenterTimer = nil
            userIsPanning = false
        }

        private func scheduleRecenter(_ mapView: MLNMapView) {
            recenterTimer?.invalidate()
            guard parent.isNavigating else { return }
            recenterTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self, weak mapView] _ in
                guard let self, let mapView else { return }
                self.userIsPanning = false
                mapView.userTrackingMode = .followWithCourse
                let center = mapView.userLocation?.coordinate ?? mapView.centerCoordinate
                let cam = MLNMapCamera(lookingAtCenter: center,
                                      altitude: 500, pitch: 60,
                                      heading: mapView.camera.heading)
                mapView.setCamera(cam, withDuration: 0.8, animationTimingFunction: nil)
            }
        }
    }
}

// MARK: - RadarMapAnnotation

final class RadarMapAnnotation: MLNPointAnnotation {
    var radar: Radar?
}

// MARK: - RadarPinView

final class RadarPinView: MLNAnnotationView {

    // Layers & subviews
    private let shadowLayer = CAShapeLayer()
    private let bodyLayer   = CAShapeLayer()
    private let rimLayer    = CAShapeLayer()
    private let gradLayer   = CAGradientLayer()
    private let iconIV      = UIImageView()
    private let vmaBg       = UIView()
    private let vmaLabel    = UILabel()

    // Sizes
    private static let normalD:   CGFloat = 36
    private static let selectedD: CGFloat = 48
    private static let normalTail:   CGFloat = 12
    private static let selectedTail: CGFloat = 16

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        isEnabled = true
        backgroundColor = .clear

        // Order: shadow → body fill (gradient) → rim → icon → VMA badge
        layer.addSublayer(shadowLayer)
        layer.addSublayer(bodyLayer)
        gradLayer.type = .axial
        gradLayer.startPoint = CGPoint(x: 0.3, y: 0)
        gradLayer.endPoint   = CGPoint(x: 0.7, y: 1)
        layer.addSublayer(gradLayer)
        layer.addSublayer(rimLayer)

        iconIV.contentMode = .scaleAspectFit
        addSubview(iconIV)

        vmaBg.backgroundColor = .white
        vmaBg.layer.borderColor = UIColor.systemRed.cgColor
        vmaBg.layer.borderWidth = 2
        addSubview(vmaBg)

        vmaLabel.textAlignment = .center
        vmaLabel.textColor = .black
        vmaBg.addSubview(vmaLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(kind: RadarKind, selected: Bool) {
        let d    = selected ? Self.selectedD    : Self.normalD
        let tail = selected ? Self.selectedTail : Self.normalTail
        let pad: CGFloat = 6          // padding around pin so shadow isn't clipped
        let vmaD: CGFloat = selected ? 24 : 18
        let totalW = d + vmaD * 0.6 + pad * 2   // room for VMA badge at top-right
        let totalH = d + tail + pad * 2

        frame = CGRect(x: 0, y: 0, width: totalW, height: totalH)

        let color = UIColor(kind.color)
        let path  = tearDrop(cx: pad + d / 2, cy: pad + d / 2, d: d, tail: tail)

        // Shadow (blurred, offset)
        shadowLayer.path        = path.cgPath
        shadowLayer.fillColor   = color.withAlphaComponent(0.45).cgColor
        shadowLayer.shadowColor = color.cgColor
        shadowLayer.shadowOpacity = 0.65
        shadowLayer.shadowRadius  = selected ? 10 : 6
        shadowLayer.shadowOffset  = CGSize(width: 0, height: selected ? 4 : 2)
        shadowLayer.frame         = bounds

        // Body solid fill (used as mask for gradient)
        let bodyMask = CAShapeLayer()
        bodyMask.path = path.cgPath
        bodyLayer.path      = path.cgPath
        bodyLayer.fillColor = color.cgColor
        bodyLayer.frame     = bounds

        // Gradient overlay (lighter top-left corner = glossy effect)
        gradLayer.frame  = CGRect(x: pad, y: pad, width: d, height: d + tail)
        gradLayer.colors = [
            color.lighter(by: 0.30).cgColor,
            color.cgColor,
            color.darker(by: 0.10).cgColor
        ]
        gradLayer.locations = [0, 0.55, 1]
        let gradMask = CAShapeLayer()
        gradMask.path = tearDrop(cx: d / 2, cy: d / 2, d: d, tail: tail).cgPath
        gradLayer.mask = gradMask

        // White inner rim
        let rimPath = UIBezierPath(
            arcCenter: CGPoint(x: pad + d / 2, y: pad + d / 2),
            radius: d / 2 - 2.5,
            startAngle: 0, endAngle: .pi * 2, clockwise: true)
        rimLayer.path        = rimPath.cgPath
        rimLayer.fillColor   = UIColor.clear.cgColor
        rimLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        rimLayer.lineWidth   = 1.5
        rimLayer.frame       = bounds

        // Icon
        let iconPt: CGFloat = d * 0.40
        let cfg = UIImage.SymbolConfiguration(pointSize: iconPt, weight: .bold)
        iconIV.image = UIImage(systemName: kind.symbol, withConfiguration: cfg)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        iconIV.frame = CGRect(x: pad, y: pad, width: d, height: d)

        // VMA badge (top-right corner)
        vmaBg.frame = CGRect(
            x: pad + d - vmaD * 0.45,
            y: pad - vmaD * 0.35,
            width: vmaD, height: vmaD)
        vmaBg.layer.cornerRadius = vmaD / 2
        vmaBg.layer.borderWidth  = vmaD <= 18 ? 1.5 : 2
        vmaBg.isHidden = true   // shown in configure(kind:vma:selected:)

        vmaLabel.font  = UIFont.systemFont(ofSize: vmaD * 0.38, weight: .black)
        vmaLabel.frame = vmaBg.bounds
    }

    func configure(kind: RadarKind, vma: Int?, selected: Bool) {
        configure(kind: kind, selected: selected)
        if let speed = vma {
            vmaBg.isHidden = false
            vmaLabel.text  = "\(speed)"
        } else {
            vmaBg.isHidden = true
        }
    }

    // MARK: - Helpers

    private func tearDrop(cx: CGFloat, cy: CGFloat, d: CGFloat, tail: CGFloat) -> UIBezierPath {
        let r = d / 2
        // Open arc from ~130° to ~50° (bottom-left to bottom-right, clockwise via top)
        let a0 = CGFloat.pi * (0.5 + 0.22)   // 144°
        let a1 = CGFloat.pi * (0.5 - 0.22)   //  36°
        let path = UIBezierPath(
            arcCenter: CGPoint(x: cx, y: cy),
            radius: r, startAngle: a0, endAngle: a1, clockwise: true)
        path.addLine(to: CGPoint(x: cx, y: cy + r + tail))
        path.close()
        return path
    }
}

// MARK: - UIColor helpers

private extension UIColor {
    func lighter(by amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: max(0, s - amount * 0.3),
                       brightness: min(1, b + amount), alpha: a)
    }
    func darker(by amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: min(1, s + amount * 0.1),
                       brightness: max(0, b - amount), alpha: a)
    }
}

// MARK: - MKPolyline helper

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                              count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}


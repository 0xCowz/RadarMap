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
        let iconSize = d * 0.56
        iconIV.image = makeRadarIcon(kind: kind, size: iconSize)
        iconIV.frame = CGRect(
            x: pad + (d - iconSize) / 2,
            y: pad + (d - iconSize) / 2,
            width: iconSize, height: iconSize)

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

    // MARK: - Custom icon rendering

    private func makeRadarIcon(kind: RadarKind, size: CGFloat) -> UIImage {
        let sz = CGSize(width: size, height: size)
        return UIGraphicsImageRenderer(size: sz).image { _ in
            switch kind {
            case .fixe:         drawCameraIcon(s: size)
            case .discriminant: drawDiscriminantIcon(s: size)
            case .feuRouge:     drawTrafficLightIcon(s: size)
            case .vitMoyenne:   drawAverageSpeedIcon(s: size)
            case .pn:           drawRailCrossingIcon(s: size)
            case .itineraire:   drawItineraireIcon(s: size)
            }
        }
    }

    private func drawCameraIcon(s: CGFloat) {
        let white = UIColor.white
        white.setFill(); white.setStroke()
        // Body
        UIBezierPath(roundedRect: CGRect(x: s*0.05, y: s*0.28, width: s*0.90, height: s*0.52),
                     cornerRadius: s*0.12).fill()
        // Viewfinder bump
        UIBezierPath(roundedRect: CGRect(x: s*0.30, y: s*0.14, width: s*0.24, height: s*0.17),
                     cornerRadius: s*0.06).fill()
        // Lens glass
        UIColor.white.withAlphaComponent(0.28).setFill()
        let lensRect = CGRect(x: s*0.30, y: s*0.34, width: s*0.40, height: s*0.40)
        UIBezierPath(ovalIn: lensRect).fill()
        // Lens ring
        white.setStroke()
        let ring = UIBezierPath(ovalIn: lensRect.insetBy(dx: s*0.03, dy: s*0.03))
        ring.lineWidth = s * 0.07; ring.stroke()
        // Lens center dot
        white.setFill()
        UIBezierPath(ovalIn: CGRect(x: s*0.42, y: s*0.46, width: s*0.16, height: s*0.16)).fill()
    }

    private func drawDiscriminantIcon(s: CGFloat) {
        let white = UIColor.white
        white.setFill(); white.setStroke()
        // Camera body
        UIBezierPath(roundedRect: CGRect(x: s*0.08, y: s*0.05, width: s*0.84, height: s*0.44),
                     cornerRadius: s*0.10).fill()
        // Lens
        let lr = CGRect(x: s*0.33, y: s*0.10, width: s*0.34, height: s*0.32)
        UIColor.white.withAlphaComponent(0.25).setFill()
        UIBezierPath(ovalIn: lr).fill()
        white.setStroke()
        let ring = UIBezierPath(ovalIn: lr.insetBy(dx: s*0.03, dy: s*0.03))
        ring.lineWidth = s * 0.065; ring.stroke()
        // Two dashed road lanes
        white.setStroke()
        for laneY in [s*0.64, s*0.84] {
            let lane = UIBezierPath()
            lane.move(to: CGPoint(x: s*0.06, y: laneY))
            lane.addLine(to: CGPoint(x: s*0.94, y: laneY))
            lane.lineWidth = s * 0.08
            lane.lineCapStyle = .round
            lane.setLineDash([s*0.14, s*0.08], count: 2, phase: 0)
            lane.stroke()
        }
    }

    private func drawTrafficLightIcon(s: CGFloat) {
        // Housing
        let housing = UIBezierPath(
            roundedRect: CGRect(x: s*0.28, y: s*0.03, width: s*0.44, height: s*0.90),
            cornerRadius: s*0.10)
        UIColor.white.withAlphaComponent(0.22).setFill(); housing.fill()
        housing.lineWidth = s * 0.07; UIColor.white.setStroke(); housing.stroke()
        // Three colored lights: red / amber / green
        let cx = s * 0.50
        let dr = s * 0.13
        let lights: [(CGFloat, UIColor)] = [
            (s*0.22, UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1)),
            (s*0.50, UIColor(red: 1.0, green: 0.72, blue: 0.00, alpha: 1)),
            (s*0.78, UIColor(red: 0.22, green: 0.90, blue: 0.35, alpha: 1)),
        ]
        for (y, color) in lights {
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: cx-dr, y: y-dr, width: dr*2, height: dr*2)).fill()
        }
    }

    private func drawAverageSpeedIcon(s: CGFloat) {
        let white = UIColor.white
        white.setFill(); white.setStroke()
        // Left post
        let lp = UIBezierPath()
        lp.move(to: CGPoint(x: s*0.22, y: s*0.15))
        lp.addLine(to: CGPoint(x: s*0.22, y: s*0.75))
        lp.lineWidth = s * 0.10; lp.lineCapStyle = .round; lp.stroke()
        // Right post
        let rp = UIBezierPath()
        rp.move(to: CGPoint(x: s*0.78, y: s*0.15))
        rp.addLine(to: CGPoint(x: s*0.78, y: s*0.75))
        rp.lineWidth = s * 0.10; rp.lineCapStyle = .round; rp.stroke()
        // Arrow shaft
        let shaft = UIBezierPath()
        shaft.move(to: CGPoint(x: s*0.22, y: s*0.45))
        shaft.addLine(to: CGPoint(x: s*0.60, y: s*0.45))
        shaft.lineWidth = s * 0.08; shaft.lineCapStyle = .round; shaft.stroke()
        // Arrow head
        let head = UIBezierPath()
        head.move(to: CGPoint(x: s*0.58, y: s*0.31))
        head.addLine(to: CGPoint(x: s*0.84, y: s*0.45))
        head.addLine(to: CGPoint(x: s*0.58, y: s*0.59))
        head.close(); head.fill()
        // Three dots (avg indicator)
        let dr = s * 0.055
        for dotX in [s*0.33, s*0.50, s*0.67] {
            UIBezierPath(ovalIn: CGRect(x: dotX-dr, y: s*0.83-dr, width: dr*2, height: dr*2)).fill()
        }
    }

    private func drawRailCrossingIcon(s: CGFloat) {
        let white = UIColor.white
        white.setFill(); white.setStroke()
        // Outer circle
        let circle = UIBezierPath(ovalIn: CGRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88))
        circle.lineWidth = s * 0.07; circle.stroke()
        // X crossbuck
        let cross = UIBezierPath()
        cross.move(to: CGPoint(x: s*0.22, y: s*0.22)); cross.addLine(to: CGPoint(x: s*0.78, y: s*0.78))
        cross.move(to: CGPoint(x: s*0.78, y: s*0.22)); cross.addLine(to: CGPoint(x: s*0.22, y: s*0.78))
        cross.lineWidth = s * 0.13; cross.lineCapStyle = .round; cross.stroke()
    }

    private func drawItineraireIcon(s: CGFloat) {
        let white = UIColor.white
        white.setFill(); white.setStroke()
        // Autoroute shield (pentagon)
        let shield = UIBezierPath()
        shield.move(to: CGPoint(x: s*0.50, y: s*0.96))
        shield.addLine(to: CGPoint(x: s*0.08, y: s*0.68))
        shield.addLine(to: CGPoint(x: s*0.08, y: s*0.10))
        shield.addLine(to: CGPoint(x: s*0.92, y: s*0.10))
        shield.addLine(to: CGPoint(x: s*0.92, y: s*0.68))
        shield.close()
        UIColor.white.withAlphaComponent(0.22).setFill(); shield.fill()
        shield.lineWidth = s * 0.07; white.setStroke(); shield.stroke()
        // "A" letter (autoroute)
        let A = UIBezierPath()
        A.move(to: CGPoint(x: s*0.26, y: s*0.78))
        A.addLine(to: CGPoint(x: s*0.50, y: s*0.20))
        A.addLine(to: CGPoint(x: s*0.74, y: s*0.78))
        A.move(to: CGPoint(x: s*0.34, y: s*0.54))
        A.addLine(to: CGPoint(x: s*0.66, y: s*0.54))
        A.lineWidth = s * 0.085; A.lineCapStyle = .round; A.lineJoinStyle = .round
        white.setStroke(); A.stroke()
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


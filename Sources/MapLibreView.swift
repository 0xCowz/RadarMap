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
        let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
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
                UIColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1))
            ext.fillExtrusionOpacity = NSExpression(forConstantValue: 0.75)
            style.addLayer(ext)
        }

        // ── Apparence carte (light / dark) ────────────────────────────────────
        private func applyAppearance(to style: MLNStyle, dark: Bool) {
            // Fond
            if let bg = style.layer(withIdentifier: "background") as? MLNBackgroundStyleLayer {
                bg.backgroundColor = NSExpression(forConstantValue:
                    dark ? UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
                         : UIColor(red: 0.94, green: 0.94, blue: 0.91, alpha: 1))
            }
            // Zones de terrain
            for id in ["landuse", "landuse-residential", "landcover-grass",
                        "landcover-wood", "landcover-scrub", "landuse-commercial",
                        "landuse-industrial"] {
                if let l = style.layer(withIdentifier: id) as? MLNFillStyleLayer {
                    l.fillColor = NSExpression(forConstantValue:
                        dark ? UIColor(red: 0.13, green: 0.15, blue: 0.17, alpha: 1)
                             : UIColor(red: 0.88, green: 0.92, blue: 0.83, alpha: 1))
                }
            }
            // Eau
            if let w = style.layer(withIdentifier: "water") as? MLNFillStyleLayer {
                w.fillColor = NSExpression(forConstantValue:
                    dark ? UIColor(red: 0.08, green: 0.14, blue: 0.25, alpha: 1)
                         : UIColor(red: 0.55, green: 0.75, blue: 0.90, alpha: 1))
            }
            // Routes
            let roadColor = dark ? UIColor(red: 0.30, green: 0.50, blue: 0.80, alpha: 1)
                                 : UIColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1)
            for id in ["road-primary", "road-secondary", "highway"] {
                if let l = style.layer(withIdentifier: id) as? MLNLineStyleLayer {
                    l.lineColor = NSExpression(forConstantValue: roadColor)
                }
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
            if let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? RadarPinView {
                v.configure(kind: radar.kind, selected: radar == parent.selectedRadar)
                return v
            }
            let v = RadarPinView(reuseIdentifier: id)
            v.configure(kind: radar.kind, selected: radar == parent.selectedRadar)
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
    private let circle  = UIView()
    private let iconIV  = UIImageView()
    private let labelBg = UIView()
    private let labelL  = UILabel()
    private let pointer = UIImageView()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        isEnabled = true
        frame = CGRect(x: 0, y: 0, width: 50, height: 62)
        backgroundColor = .clear

        circle.layer.cornerRadius  = 16
        circle.layer.borderColor   = UIColor.white.withAlphaComponent(0.5).cgColor
        circle.layer.borderWidth   = 2
        circle.layer.shadowColor   = UIColor.black.cgColor
        circle.layer.shadowOpacity = 0.3
        circle.layer.shadowRadius  = 4
        circle.layer.shadowOffset  = CGSize(width: 0, height: 2)
        addSubview(circle)

        iconIV.contentMode = .scaleAspectFit
        addSubview(iconIV)

        labelBg.layer.cornerRadius = 5
        labelBg.layer.masksToBounds = true
        addSubview(labelBg)

        labelL.font          = UIFont.systemFont(ofSize: 8, weight: .bold)
        labelL.textColor     = .white
        labelL.textAlignment = .center
        labelBg.addSubview(labelL)

        let cfg = UIImage.SymbolConfiguration(pointSize: 6, weight: .bold)
        pointer.image = UIImage(systemName: "arrowtriangle.down.fill", withConfiguration: cfg)
        pointer.contentMode = .scaleAspectFit
        addSubview(pointer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(kind: RadarKind, selected: Bool) {
        let size: CGFloat = selected ? 40 : 30
        let color = UIColor(kind.color)

        circle.frame = CGRect(x: (50 - size) / 2, y: 0, width: size, height: size)
        circle.layer.cornerRadius = size / 2
        circle.backgroundColor = color

        let cfg = UIImage.SymbolConfiguration(pointSize: selected ? 16 : 12, weight: .bold)
        iconIV.image = UIImage(systemName: kind.symbol, withConfiguration: cfg)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        iconIV.frame = circle.frame

        labelL.text = kind.shortLabel
        let w: CGFloat = 46
        labelBg.frame = CGRect(x: 2, y: size + 2, width: w, height: 13)
        labelBg.backgroundColor = color.withAlphaComponent(0.88)
        labelL.frame = labelBg.bounds

        pointer.tintColor = color
        pointer.image = pointer.image?.withTintColor(color, renderingMode: .alwaysOriginal)
        pointer.frame = CGRect(x: 19, y: size + 15, width: 12, height: 8)

        frame.size.height = size + 24
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


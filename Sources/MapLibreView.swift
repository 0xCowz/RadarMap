import MapLibre
import MapKit
import SwiftUI
import UIKit

// MARK: - MapLibreView (UIViewRepresentable)

struct MapLibreView: UIViewRepresentable {
    @Binding var selectedRadar: Radar?
    @Binding var route: MKRoute?
    var radars: [Radar]
    var onRegionChange: ((CLLocationCoordinate2D, Double) -> Void)?

    func makeUIView(context: Context) -> MLNMapView {
        // OpenFreeMap – style vecteur gratuit, sans clé API
        let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.logoView.isHidden = false  // attribution requise
        mapView.attributionButton.isHidden = false
        mapView.compassView.compassVisibility = .adaptive

        // Vue 3D initiale sur Paris
        let camera = MLNMapCamera()
        camera.centerCoordinate = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        camera.altitude = 6000
        camera.pitch = 55
        camera.heading = 0
        mapView.setCamera(camera, animated: false)

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        // Mise à jour des annotations radar
        context.coordinator.updateRadarAnnotations(on: mapView, radars: radars, selected: selectedRadar)
        // Mise à jour de l'itinéraire
        context.coordinator.updateRoute(on: mapView, route: route)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreView
        private var styleLoaded = false
        private var pendingRadars: [Radar]?
        private var pendingSelected: Radar?
        private var pendingRoute: MKRoute?

        init(_ parent: MapLibreView) {
            self.parent = parent
        }

        // ── Style chargé ────────────────────────────────────────────────────
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleLoaded = true
            apply3DBuildings(to: style)
            applyCustomAppearance(to: style)
            if let radars = pendingRadars {
                updateRadarAnnotations(on: mapView, radars: radars, selected: pendingSelected)
                pendingRadars = nil
            }
            if let route = pendingRoute {
                updateRoute(on: mapView, route: route)
                pendingRoute = nil
            }
        }

        // ── Bâtiments 3D ────────────────────────────────────────────────────
        private func apply3DBuildings(to style: MLNStyle) {
            guard let source = style.source(withIdentifier: "openmaptiles") else { return }

            // Supprimer l'ancien calque 2D de bâtiments si présent
            if let old = style.layer(withIdentifier: "building") { style.removeLayer(old) }

            let extrusion = MLNFillExtrusionStyleLayer(
                identifier: "3d-buildings", source: source)
            extrusion.sourceLayerIdentifier = "building"
            extrusion.predicate = NSPredicate(format: "render_height > 0 OR render_height == 0")
            extrusion.fillExtrusionBase   = NSExpression(forKeyPath: "render_min_height")
            extrusion.fillExtrusionHeight = NSExpression(forKeyPath: "render_height")
            extrusion.fillExtrusionColor  = NSExpression(forConstantValue:
                UIColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1))
            extrusion.fillExtrusionOpacity = NSExpression(forConstantValue: 0.75)
            style.addLayer(extrusion)
        }

        // ── Apparence de la carte ────────────────────────────────────────────
        private func applyCustomAppearance(to style: MLNStyle) {
            // Route principale en bleu profond
            for layerID in ["road-primary", "road-secondary", "highway"] {
                if let layer = style.layer(withIdentifier: layerID) as? MLNLineStyleLayer {
                    layer.lineColor = NSExpression(forConstantValue:
                        UIColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1))
                }
            }
            // Autoroutes en rouge discret
            if let hw = style.layer(withIdentifier: "highway_name_major") as? MLNSymbolStyleLayer {
                hw.textColor = NSExpression(forConstantValue: UIColor.darkGray)
            }
        }

        // ── Annotations radar ────────────────────────────────────────────────
        func updateRadarAnnotations(on mapView: MLNMapView, radars: [Radar], selected: Radar?) {
            guard styleLoaded else {
                pendingRadars  = radars
                pendingSelected = selected
                return
            }

            // Supprimer les anciennes
            if let existing = mapView.annotations?.compactMap({ $0 as? RadarMapAnnotation }) {
                mapView.removeAnnotations(existing)
            }

            // Ajouter les nouvelles
            let annotations = radars.map { radar -> RadarMapAnnotation in
                let ann = RadarMapAnnotation()
                ann.radar      = radar
                ann.coordinate = radar.coordinate
                ann.title      = radar.kind.label
                ann.subtitle   = radar.vmaText
                return ann
            }
            if !annotations.isEmpty {
                mapView.addAnnotations(annotations)
            }
        }

        // ── Itinéraire ───────────────────────────────────────────────────────
        func updateRoute(on mapView: MLNMapView, route: MKRoute?) {
            guard styleLoaded else {
                pendingRoute = route
                return
            }

            // Nettoyer
            if let s = mapView.style {
                ["route-casing", "route-line"].forEach { id in
                    if let l = s.layer(withIdentifier: id) { s.removeLayer(l) }
                }
                if let src = s.source(withIdentifier: "route-source") { s.removeSource(src) }
            }

            guard let route, let style = mapView.style else { return }

            var coords = route.polyline.coordinates
            let polyline = MLNPolylineFeature(coordinates: &coords,
                                              count: UInt(coords.count))
            let source = MLNShapeSource(identifier: "route-source",
                                        features: [polyline], options: nil)
            style.addSource(source)

            // Contour blanc
            let casing = MLNLineStyleLayer(identifier: "route-casing", source: source)
            casing.lineColor   = NSExpression(forConstantValue: UIColor.white)
            casing.lineWidth   = NSExpression(forConstantValue: 9)
            casing.lineCap     = NSExpression(forConstantValue: "round")
            casing.lineJoin    = NSExpression(forConstantValue: "round")
            style.addLayer(casing)

            // Ligne bleue principale
            let line = MLNLineStyleLayer(identifier: "route-line", source: source)
            line.lineColor = NSExpression(forConstantValue:
                UIColor(red: 0.12, green: 0.47, blue: 1.0, alpha: 1))
            line.lineWidth = NSExpression(forConstantValue: 6)
            line.lineCap   = NSExpression(forConstantValue: "round")
            line.lineJoin  = NSExpression(forConstantValue: "round")
            style.addLayer(line)

            // Centrer sur le début de l'itinéraire
            if coords.count > 0 {
                let cam = MLNMapCamera()
                cam.centerCoordinate = coords[coords.count / 4]
                cam.altitude = 8000
                cam.pitch    = 55
                mapView.setCamera(cam, withDuration: 1.2, animationTimingFunction: nil)
            }
        }

        // ── Vue d'annotation ─────────────────────────────────────────────────
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let ann = annotation as? RadarMapAnnotation,
                  let radar = ann.radar else { return nil }

            let reuseID = "pin-\(radar.kind.rawValue)"
            if let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                           as? RadarPinView {
                view.configure(kind: radar.kind,
                               selected: radar == parent.selectedRadar)
                return view
            }
            let view = RadarPinView(reuseIdentifier: reuseID)
            view.configure(kind: radar.kind, selected: radar == parent.selectedRadar)
            return view
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard let ann = annotation as? RadarMapAnnotation,
                  let radar = ann.radar else { return }
            DispatchQueue.main.async { self.parent.selectedRadar = radar }
        }

        func mapView(_ mapView: MLNMapView, didDeselect annotation: MLNAnnotation) {
            // Ne pas fermer la sheet automatiquement
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason,
                     animated: Bool) {
            let center   = mapView.centerCoordinate
            let altitude = mapView.camera.altitude
            parent.onRegionChange?(center, altitude)
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

    private var kind: RadarKind = .fixe

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        isEnabled = true
        frame = CGRect(x: 0, y: 0, width: 50, height: 62)
        backgroundColor = .clear

        // Circle (glow + fill)
        circle.layer.cornerRadius  = 16
        circle.layer.borderColor   = UIColor.white.withAlphaComponent(0.5).cgColor
        circle.layer.borderWidth   = 2
        circle.layer.shadowColor   = UIColor.black.cgColor
        circle.layer.shadowOpacity = 0.3
        circle.layer.shadowRadius  = 4
        circle.layer.shadowOffset  = CGSize(width: 0, height: 2)
        addSubview(circle)

        // Icon
        iconIV.contentMode = .scaleAspectFit
        addSubview(iconIV)

        // Label background
        labelBg.layer.cornerRadius = 5
        labelBg.layer.masksToBounds = true
        addSubview(labelBg)

        // Label text
        labelL.font          = UIFont.systemFont(ofSize: 8, weight: .bold)
        labelL.textColor     = .white
        labelL.textAlignment = .center
        labelBg.addSubview(labelL)

        // Pointer triangle
        let cfg = UIImage.SymbolConfiguration(pointSize: 6, weight: .bold)
        pointer.image = UIImage(systemName: "arrowtriangle.down.fill",
                                withConfiguration: cfg)
        pointer.contentMode = .scaleAspectFit
        addSubview(pointer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(kind: RadarKind, selected: Bool) {
        self.kind = kind
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
        labelL.frame  = labelBg.bounds

        pointer.tintColor   = color
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

// MARK: - UIColor from SwiftUI Color

extension UIColor {
    convenience init(_ color: Color) {
        let resolved = UIColor(color)
        self.init(cgColor: resolved.cgColor ?? UIColor.red.cgColor)
    }
}

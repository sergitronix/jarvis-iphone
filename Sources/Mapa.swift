import SwiftUI
import MapKit
import CoreLocation

final class Ubicacion: NSObject, ObservableObject, CLLocationManagerDelegate {
    let lm = CLLocationManager()
    @Published var punto: CLLocationCoordinate2D?
    override init() {
        super.init()
        lm.delegate = self; lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.requestWhenInUseAuthorization(); lm.startUpdatingLocation()
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) { punto = l.last?.coordinate }
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) { if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways { m.startUpdatingLocation() } }
}

struct MapaBase: UIViewRepresentable {
    var centro: CLLocationCoordinate2D?
    var destino: MKMapItem?
    var tipo: MKMapType
    func makeUIView(context: Context) -> MKMapView {
        let v = MKMapView()
        v.overrideUserInterfaceStyle = .dark
        v.showsUserLocation = true; v.showsCompass = false; v.pointOfInterestFilter = .includingAll
        v.mapType = tipo
        return v
    }
    func updateUIView(_ v: MKMapView, context: Context) {
        v.mapType = tipo
        v.removeAnnotations(v.annotations.filter { !($0 is MKUserLocation) })
        if let d = destino {
            v.addAnnotation(d.placemark)
            v.setRegion(MKCoordinateRegion(center: d.placemark.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500), animated: true)
            context.coordinator.centrado = true
        } else if let c = centro, !context.coordinator.centrado {
            v.setRegion(MKCoordinateRegion(center: c, latitudinalMeters: 1200, longitudinalMeters: 1200), animated: false)
            context.coordinator.centrado = true
        }
    }
    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var centrado = false }
}

struct MapaHolo: View {
    var consulta: String?
    var onCerrar: () -> Void
    @StateObject var ubi = Ubicacion()
    @State var destino: MKMapItem?
    @State var satelite = false
    @State var estado = "UBICANDO..."

    var body: some View {
        ZStack {
            FONDO.ignoresSafeArea()
            MapaBase(centro: ubi.punto, destino: destino, tipo: satelite ? .hybrid : .mutedStandard)
                .saturation(0.15).contrast(1.15).colorMultiply(CIAN).brightness(0.02)
                .overlay(Rejilla().allowsHitTesting(false))
                .overlay(
                    TimelineView(.animation) { tl in
                        GeometryReader { g in
                            let ph = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.5) / 3.5
                            LinearGradient(colors: [.clear, CIAN.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 70).offset(y: CGFloat(ph) * (g.size.height + 70) - 70)
                        }
                    }.allowsHitTesting(false).clipped())
                .overlay(RadialGradient(colors: [.clear, FONDO.opacity(0.75)], center: .center, startRadius: 160, endRadius: 520).allowsHitTesting(false))
                .overlay(Esquinas(l: 28).stroke(CIAN, lineWidth: 2).padding(10).allowsHitTesting(false))
                .padding(.vertical, 60).ignoresSafeArea(edges: .horizontal)
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("M A P A   H O L O").font(.system(size: 18, weight: .light, design: .monospaced)).foregroundColor(CIAN)
                        Text(destino?.name?.uppercased() ?? estado).font(.system(size: 10, design: .monospaced)).foregroundColor(ORO)
                    }
                    Spacer()
                    Button(action: onCerrar) {
                        Image(systemName: "xmark").foregroundColor(CIAN).frame(width: 36, height: 36)
                            .overlay(Circle().stroke(CIAN.opacity(0.7), lineWidth: 1.5))
                    }
                }.padding(.horizontal, 18).padding(.top, 8)
                Spacer()
                HStack {
                    if let p = ubi.punto {
                        Text(String(format: "LAT %.4f   LON %.4f", p.latitude, p.longitude)).font(.system(size: 10, design: .monospaced)).foregroundColor(CIAN.opacity(0.8))
                    }
                    Spacer()
                    Button(action: { destino = nil; satelite.toggle() }) {
                        Text(satelite ? "VISTA SATÉLITE" : "VISTA HOLO").font(.system(size: 10, design: .monospaced)).foregroundColor(ORO)
                            .padding(.horizontal, 8).padding(.vertical, 4).overlay(Esquinas(l: 5).stroke(ORO, lineWidth: 1))
                    }
                    Button(action: { if let d = destino { d.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]) } }) {
                        Text("RUTA").font(.system(size: 10, design: .monospaced)).foregroundColor(destino == nil ? CIAN.opacity(0.3) : CIAN)
                            .padding(.horizontal, 8).padding(.vertical, 4).overlay(Esquinas(l: 5).stroke(CIAN.opacity(destino == nil ? 0.3 : 1), lineWidth: 1))
                    }
                }.padding(.horizontal, 18).padding(.bottom, 10)
            }
        }
        .onAppear { if let c = consulta, !c.isEmpty { buscar(c) } }
        .onChange(of: ubi.punto == nil) { _ in estado = "POSICIÓN ACTUAL" }
    }

    func buscar(_ q: String) {
        estado = "BUSCANDO " + q.uppercased()
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = q
        if let p = ubi.punto { r.region = MKCoordinateRegion(center: p, latitudinalMeters: 20000, longitudinalMeters: 20000) }
        MKLocalSearch(request: r).start { resp, _ in
            DispatchQueue.main.async {
                if let m = resp?.mapItems.first { destino = m } else { estado = "SIN RESULTADOS" }
            }
        }
    }
}

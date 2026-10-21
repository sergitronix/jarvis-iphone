import SwiftUI
import AVFoundation
import CoreImage

final class Camara: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let salida = AVCaptureVideoDataOutput()
    let cola = DispatchQueue(label: "cam.frames")
    let ctx = CIContext()
    private var ultimo: CVPixelBuffer?
    private let cerrojo = NSLock()

    func iniciar() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { return }
            DispatchQueue.global().async {
                if self.session.inputs.isEmpty {
                    self.session.automaticallyConfiguresApplicationAudioSession = false
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .hd1280x720
                    if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                       let inp = try? AVCaptureDeviceInput(device: dev), self.session.canAddInput(inp) { self.session.addInput(inp) }
                    self.salida.alwaysDiscardsLateVideoFrames = true
                    self.salida.setSampleBufferDelegate(self, queue: self.cola)
                    if self.session.canAddOutput(self.salida) { self.session.addOutput(self.salida) }
                    if let c = self.salida.connection(with: .video), c.isVideoOrientationSupported { c.videoOrientation = .portrait }
                    self.session.commitConfiguration()
                }
                self.session.startRunning()
            }
        }
    }

    func parar() { DispatchQueue.global().async { self.session.stopRunning() } }

    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        cerrojo.lock(); ultimo = pb; cerrojo.unlock()
    }

    // Foto interna del último fotograma, sin sonido ni salir de la cámara.
    func fotoActual() -> Data? {
        cerrojo.lock(); let pb = ultimo; cerrojo.unlock()
        guard let pb = pb else { return nil }
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        let img = UIImage(cgImage: cg)
        let m = max(img.size.width, img.size.height)
        let k = min(1, 1024 / m)
        let ns = CGSize(width: img.size.width * k, height: img.size.height * k)
        let r = UIGraphicsImageRenderer(size: ns).image { _ in img.draw(in: CGRect(origin: .zero, size: ns)) }
        return r.jpegData(compressionQuality: 0.7)
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var capa: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct PreviewCam: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView(); v.capa.session = session; v.capa.videoGravity = .resizeAspectFill; return v
    }
    func updateUIView(_ v: PreviewUIView, context: Context) {}
}

// Modo cámara en vivo: hablas con Jarvis mientras enseñas cosas; cada pregunta lleva una foto interna.
struct CamaraVivo: View {
    @StateObject var cam = Camara()
    @ObservedObject var voz: Voz
    @ObservedObject var brain: Brain
    var preguntaInicial: String
    var onCerrar: () -> Void
    @State var abierta = true
    @State var ultimaResp = ""
    @State var ultimaPreg = ""
    @State var flash = false
    let tic = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var estadoTxt: String { voz.oyendo ? "ESCUCHANDO" : (brain.pensando ? "MIRANDO Y PENSANDO" : (voz.hablando ? "HABLANDO · TOCA PARA CALLAR" : "PREPARANDO")) }
    var col: Color { voz.oyendo ? ORO : CIAN }

    func cerrar() {
        abierta = false
        voz.callar(); if voz.oyendo { voz.terminar() }
        voz.onFinal = nil
        cam.parar(); onCerrar()
    }

    func preguntar(_ t: String) {
        guard abierta else { return }
        let pl = t.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        if ["cierra la camara", "cerrar camara", "salir de la camara", "apaga la camara", "quita la camara"].contains(where: { pl.contains($0) }) { cerrar(); return }
        ultimaPreg = t; ultimaResp = ""
        flash = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { flash = false }
        let foto = cam.fotoActual()
        Registro.add("camara vivo: pregunta con foto \(foto.map { $0.count / 1024 } ?? 0)KB")
        Task {
            var r = await brain.responder(t + " (Estás viendo lo que Sergio enseña con la cámara en directo. Responde en pocas frases, para leerlo en voz alta.)", imagen: foto)
            if r.hasPrefix("Error:") { r = "No pude analizarlo, prueba otra vez." }
            guard abierta else { return }
            ultimaResp = r
            voz.hablar(r)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PreviewCam(session: cam.session).ignoresSafeArea()
                .onTapGesture { if voz.hablando { voz.callar() } }
            if flash { Color.white.opacity(0.25).ignoresSafeArea().allowsHitTesting(false) }
            Esquinas(l: 36).stroke(col, lineWidth: 2.5).padding(22).allowsHitTesting(false)
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(col).frame(width: 8, height: 8)
                        Text(estadoTxt).font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(2).foregroundColor(col)
                    }.padding(.horizontal, 10).padding(.vertical, 5).background(Color.black.opacity(0.55))
                    .overlay(Esquinas(l: 6).stroke(col, lineWidth: 1))
                    Spacer()
                    Button(action: cerrar) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            .frame(width: 42, height: 42).background(Circle().fill(Color.black.opacity(0.55)))
                    }
                }.padding(.horizontal, 30).padding(.top, 36)
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    if voz.oyendo && !voz.parcial.isEmpty { Text(voz.parcial).foregroundColor(ORO) }
                    else if !ultimaPreg.isEmpty { Text(ultimaPreg).foregroundColor(ORO.opacity(0.9)) }
                    if !ultimaResp.isEmpty { Text(ultimaResp).foregroundColor(.white) }
                    if ultimaResp.isEmpty && ultimaPreg.isEmpty && !voz.oyendo { Text("Enséñame algo y pregúntame. Di «cierra la cámara» para salir.").foregroundColor(CIAN.opacity(0.9)) }
                }
                .font(.system(size: 15, design: .rounded)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(Color.black.opacity(0.6))
                .overlay(Esquinas(l: 10).stroke(CIAN, lineWidth: 1.5))
                .padding(.horizontal, 30).padding(.bottom, 40)
            }
        }
        .onReceive(tic) { _ in
            if abierta && !voz.oyendo && !voz.hablando && !brain.pensando { voz.escuchar() }
        }
        .onAppear {
            cam.iniciar()
            voz.onFinal = { t in preguntar(t) }
            let p = preguntaInicial.trimmingCharacters(in: .whitespaces)
            if !p.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { preguntar(p) } }
        }
        .onDisappear { abierta = false; cam.parar() }
    }
}

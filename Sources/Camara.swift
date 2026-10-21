
import SwiftUI
import AVFoundation

final class Camara: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    let output = AVCapturePhotoOutput()
    var cb: ((Data?) -> Void)?

    func iniciar() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { return }
            DispatchQueue.global().async {
                if self.session.inputs.isEmpty {
                    self.session.automaticallyConfiguresApplicationAudioSession = false
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo
                    if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                       let inp = try? AVCaptureDeviceInput(device: dev), self.session.canAddInput(inp) { self.session.addInput(inp) }
                    if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                    self.session.commitConfiguration()
                }
                self.session.startRunning()
            }
        }
    }

    func parar() { DispatchQueue.global().async { self.session.stopRunning() } }

    func capturar(_ cb: @escaping (Data?) -> Void) {
        self.cb = cb
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ o: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let d = photo.fileDataRepresentation(), let img = UIImage(data: d) else { DispatchQueue.main.async { self.cb?(nil) }; return }
        let m = max(img.size.width, img.size.height)
        let k = min(1, 1024 / m)
        let ns = CGSize(width: img.size.width * k, height: img.size.height * k)
        let r = UIGraphicsImageRenderer(size: ns).image { _ in img.draw(in: CGRect(origin: .zero, size: ns)) }
        let j = r.jpegData(compressionQuality: 0.7)
        DispatchQueue.main.async { self.cb?(j) }
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

struct CamaraSheet: View {
    @StateObject var cam = Camara()
    var auto: Bool
    var onFoto: (Data) -> Void
    var onCerrar: () -> Void
    @State var cuenta = 0
    @State var hecho = false

    func disparar() {
        guard !hecho else { return }
        hecho = true
        cam.capturar { d in
            cam.parar()
            if let d = d { onFoto(d) }
            onCerrar()
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PreviewCam(session: cam.session).ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button(action: { cam.parar(); onCerrar() }) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            .frame(width: 42, height: 42).background(Circle().fill(Color.black.opacity(0.5)))
                    }
                }.padding()
                Spacer()
                if auto && cuenta > 0 {
                    Text("\(cuenta)").font(.system(size: 64, weight: .light, design: .monospaced)).foregroundColor(CIAN)
                }
                Spacer()
                Button(action: disparar) {
                    ZStack {
                        Circle().stroke(CIAN, lineWidth: 3).frame(width: 78, height: 78)
                        Circle().fill(CIAN.opacity(0.9)).frame(width: 62, height: 62)
                    }
                }.padding(.bottom, 30)
            }
        }
        .onAppear {
            cam.iniciar()
            if auto {
                cuenta = 3
                for i in 1...3 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i)) { cuenta = 3 - i; if i == 3 { disparar() } } }
            }
        }
    }
}

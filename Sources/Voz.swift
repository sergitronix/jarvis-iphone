import Foundation
import AVFoundation
import Speech

final class Voz: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    let synth = AVSpeechSynthesizer()
    let engine = AVAudioEngine()
    var req: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    let rec = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    @Published var oyendo = false
    @Published var hablando = false
    @Published var parcial = ""
    var onFinal: ((String) -> Void)?
    var timer: Timer?

    override init() { super.init(); synth.delegate = self }

    func permisos() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    func escuchar() {
        if oyendo { terminar(); return }
        synth.stopSpeaking(at: .immediate)
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? s.setActive(true)
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        req = r
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] b, _ in self?.req?.append(b) }
        engine.prepare()
        do { try engine.start() } catch { return }
        oyendo = true
        parcial = ""
        reiniciarTimer(6.0)
        task = rec?.recognitionTask(with: r) { [weak self] result, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let res = result {
                    self.parcial = res.bestTranscription.formattedString
                    self.reiniciarTimer(1.6)
                    if res.isFinal { self.terminar() }
                }
                if err != nil { self.terminar() }
            }
        }
    }

    func reiniciarTimer(_ t: Double) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in self?.terminar() }
    }

    func terminar() {
        guard oyendo else { return }
        oyendo = false
        timer?.invalidate()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        req?.endAudio()
        task?.cancel()
        let t = parcial
        parcial = ""
        if !t.trimmingCharacters(in: .whitespaces).isEmpty { onFinal?(t) }
    }

    func hablar(_ texto: String) {
        let u = AVSpeechUtterance(string: texto)
        u.voice = AVSpeechSynthesisVoice(language: "es-MX") ?? AVSpeechSynthesisVoice(language: "es-ES")
        u.rate = 0.5
        hablando = true
        synth.speak(u)
    }

    func callar() { synth.stopSpeaking(at: .immediate) }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { DispatchQueue.main.async { self.hablando = false } }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { DispatchQueue.main.async { self.hablando = false } }
}

import Foundation
import AVFoundation
import Speech
import AudioToolbox
import UIKit

final class Voz: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    var player: AVAudioPlayer?
    var gen = 0
    let synth = AVSpeechSynthesizer()
    let engine = AVAudioEngine()
    var req: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    let rec = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    @Published var oyendo = false
    @Published var hablando = false
    @Published var parcial = ""
    var onFinal: ((String) -> Void)?
    @Published var manosLibres = false
    @Published var activo = false
    @Published var segundoPlano: Bool = (UserDefaults.standard.object(forKey: "segundoPlano") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(segundoPlano, forKey: "segundoPlano") }
    }
    var enSegundo = false
    func cambioFase(_ activa: Bool) {
        enSegundo = !activa
        if enSegundo && !segundoPlano { cerrarCiclo(); activo = false }
    }
    var bloqueado = false
    var cicloActivo = false
    var tapPuesto = false
    var reqM: SFSpeechAudioBufferRecognitionRequest?
    var taskM: SFSpeechRecognitionTask?
    var silTimer: Timer?
    var cicloTimer: Timer?
    var vigilante: Timer?
    var ventanaHasta = Date.distantPast
    var viaVentana = false

    func plano(_ t: String) -> String { t.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es")) }

    func alternarManos() {
        manosLibres.toggle()
        UIApplication.shared.isIdleTimerDisabled = manosLibres
        if manosLibres {
            vigilante?.invalidate()
            vigilante = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.arrancarCiclo() }
            arrancarCiclo()
        } else {
            vigilante?.invalidate(); vigilante = nil
            cerrarCiclo()
            engine.stop(); engine.inputNode.removeTap(onBus: 0); tapPuesto = false
            activo = false
        }
    }

    func arrancarCiclo() {
        guard manosLibres, !cicloActivo, !hablando, !oyendo, !bloqueado, !(enSegundo && !segundoPlano), let rec = rec, rec.isAvailable else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? s.setActive(true)
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        reqM = r
        if !engine.isRunning || !tapPuesto {
            let input = engine.inputNode
            let fmt = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] b, _ in self?.reqM?.append(b) }
            tapPuesto = true
            engine.prepare()
            do { try engine.start() } catch { tapPuesto = false; return }
        }
        cicloActivo = true
        viaVentana = Date() < ventanaHasta
        activo = viaVentana
        cicloTimer?.invalidate()
        cicloTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in self?.cerrarCiclo() }
        taskM = rec.recognitionTask(with: r) { [weak self] result, err in
            DispatchQueue.main.async {
                guard let self = self, self.reqM === r else { return }
                if let res = result { self.procesarM(res.bestTranscription.formattedString) }
                if err != nil || (result?.isFinal ?? false) { self.cerrarCiclo() }
            }
        }
    }

    func cerrarCiclo() {
        guard cicloActivo else { return }
        cicloActivo = false
        silTimer?.invalidate(); cicloTimer?.invalidate()
        if !manosLibres { engine.stop(); engine.inputNode.removeTap(onBus: 0); tapPuesto = false }
        reqM?.endAudio()
        taskM?.cancel()
        reqM = nil; taskM = nil
        if !hablando { activo = false }
    }

    func procesarM(_ t: String) {
        let p = plano(t)
        var cmd = ""
        if let rg = p.range(of: "jarvis", options: .backwards) {
            if !activo { AudioServicesPlaySystemSound(1113) }
            activo = true
            cmd = String(t.dropFirst(p.distance(from: p.startIndex, to: rg.upperBound)))
        } else if viaVentana && activo {
            cmd = t
        } else { return }
        cmd = cmd.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?¿¡"))
        silTimer?.invalidate()
        if cmd.isEmpty {
            silTimer = Timer.scheduledTimer(withTimeInterval: 7.0, repeats: false) { [weak self] _ in
                self?.activo = false; self?.viaVentana = false; self?.cerrarCiclo()
            }
        } else {
            silTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.viaVentana = false
                self.cerrarCiclo()
                self.activo = false
                self.onFinal?(cmd)
            }
        }
    }
    var timer: Timer?

    override init() {
        super.init(); synth.delegate = self
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self = self, self.manosLibres,
                  let t = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, AVAudioSession.InterruptionType(rawValue: t) == .ended else { return }
            self.cerrarCiclo(); self.engine.stop(); self.tapPuesto = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.arrancarCiclo() }
        }
    }

    func permisos() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    func escuchar() {
        if oyendo { terminar(); return }
        cerrarCiclo()
        gen += 1; player?.stop(); hablando = false; synth.stopSpeaking(at: .immediate)
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
        tapPuesto = false
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
        tapPuesto = false
        req?.endAudio()
        task?.cancel()
        let t = parcial
        parcial = ""
        if !t.trimmingCharacters(in: .whitespaces).isEmpty { onFinal?(t) }
    }

    func hablar(_ texto: String) {
        gen += 1
        let mi = gen
        hablando = true
        cerrarCiclo()
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? s.setActive(true)
        Task { @MainActor in
            let data = await EdgeTTS.sintetizar(texto)
            guard mi == self.gen else { return }
            if let data = data, let p = try? AVAudioPlayer(data: data) {
                self.player = p
                p.delegate = self
                p.play()
            } else {
                let u = AVSpeechUtterance(string: texto)
                u.voice = AVSpeechSynthesisVoice(language: "es-MX") ?? AVSpeechSynthesisVoice(language: "es-ES")
                u.rate = 0.5
                self.synth.speak(u)
            }
        }
    }

    func callar() { gen += 1; player?.stop(); synth.stopSpeaking(at: .immediate); hablando = false }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully ok: Bool) { DispatchQueue.main.async { self.hablando = false; self.ventanaHasta = Date().addingTimeInterval(8); self.arrancarCiclo() } }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { DispatchQueue.main.async { self.hablando = false; self.ventanaHasta = Date().addingTimeInterval(8); self.arrancarCiclo() } }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { DispatchQueue.main.async { self.hablando = false } }
}

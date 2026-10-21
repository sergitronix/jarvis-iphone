
import Foundation
import UserNotifications
import AudioToolbox

final class Reloj: ObservableObject {
    @Published var cronoInicio: Date?
    @Published var cronoAcum: TimeInterval = 0
    @Published var cronoCorre = false
    @Published var tempFin: Date?
    var tempTotal: TimeInterval = 0
    var disparo: Timer?

    static func fmt(_ t: TimeInterval, dec: Bool) -> String {
        let n = max(0, t)
        let h = Int(n) / 3600, m = (Int(n) % 3600) / 60, s = Int(n) % 60
        let d = Int((n - floor(n)) * 10)
        var r = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
        if dec { r += ".\(d)" }
        return r
    }

    func cronoTexto(_ ahora: Date) -> String {
        Reloj.fmt(cronoAcum + (cronoCorre ? ahora.timeIntervalSince(cronoInicio ?? ahora) : 0), dec: true)
    }

    func tempRestante(_ ahora: Date) -> TimeInterval? {
        guard let f = tempFin else { return nil }
        return max(0, f.timeIntervalSince(ahora))
    }

    var activo: Bool { cronoCorre || cronoAcum > 0 || tempFin != nil }

    func plano(_ t: String) -> String {
        t.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
    }

    func duracion(_ s: String) -> TimeInterval {
        var total: TimeInterval = 0
        var s = s
        let nums: [(String, String)] = [("cuarenta y cinco", "45"), ("veinticinco", "25"), ("treinta", "30"), ("cuarenta", "40"), ("cincuenta", "50"), ("sesenta", "60"), ("quince", "15"), ("veinte", "20"), ("diez", "10"), ("nueve", "9"), ("ocho", "8"), ("siete", "7"), ("seis", "6"), ("cinco", "5"), ("cuatro", "4"), ("tres", "3"), ("dos", "2")]
        for (w, n) in nums { s = s.replacingOccurrences(of: "\\b" + w + "\\b", with: n, options: .regularExpression) }
        let pat = "(\\d+(?:[.,]\\d+)?|un|una|medio|media)\\s*(horas?|hs?|minutos?|mins?|segundos?|segs?)\\b"
        guard let re = try? NSRegularExpression(pattern: pat) else { return 0 }
        let ns = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let n = ns.substring(with: m.range(at: 1)), u = ns.substring(with: m.range(at: 2))
            let v: Double = (n == "un" || n == "una") ? 1 : ((n == "medio" || n == "media") ? 0.5 : (Double(n.replacingOccurrences(of: ",", with: ".")) ?? 0))
            if u.hasPrefix("h") { total += v * 3600 } else if u.hasPrefix("m") { total += v * 60 } else { total += v }
        }
        if s.contains("hora y media") { total += 1800 }
        if s.contains("minuto y medio") { total += 30 }
        return total
    }

    func procesar(_ texto: String) -> String? {
        let s = plano(texto)
        let pal = Set(s.split(whereSeparator: { !$0.isLetter }).map(String.init))
        func tiene(_ l: [String]) -> Bool { l.contains(where: { pal.contains($0) }) }
        if s.contains("cronometro") {
            let ahora = Date()
            if tiene(["borra", "reinicia", "resetea", "cero", "quita", "reset"]) {
                cronoCorre = false; cronoAcum = 0; cronoInicio = nil; return "Cronómetro a cero."
            }
            if tiene(["para", "parar", "detener", "deten", "detenlo", "pausa", "stop"]) {
                if cronoCorre { cronoAcum += ahora.timeIntervalSince(cronoInicio ?? ahora); cronoCorre = false }
                return "Cronómetro parado en " + Reloj.fmt(cronoAcum, dec: false) + "."
            }
            if !cronoCorre { cronoInicio = ahora; cronoCorre = true }
            return "Cronómetro en marcha."
        }
        if s.contains("temporizador") || s.contains("cuenta atras") || s.contains("alarma de") {
            let dur = duracion(s)
            if dur <= 0 {
                if s.contains("cancel") || tiene(["quita", "borra", "para", "parar", "deten", "detener", "apaga"]) {
                    cancelar(); return "Temporizador cancelado."
                }
                return "¿De cuánto lo quieres?"
            }
            iniciar(dur)
            return "Temporizador de " + descripcion(dur) + "."
        }
        return nil
    }

    func descripcion(_ d: TimeInterval) -> String {
        let h = Int(d) / 3600, m = (Int(d) % 3600) / 60, s = Int(d) % 60
        var p: [String] = []
        if h > 0 { p.append("\(h) hora" + (h > 1 ? "s" : "")) }
        if m > 0 { p.append("\(m) minuto" + (m > 1 ? "s" : "")) }
        if s > 0 { p.append("\(s) segundo" + (s > 1 ? "s" : "")) }
        return p.joined(separator: " y ")
    }

    func iniciar(_ dur: TimeInterval) {
        cancelar()
        tempTotal = dur
        tempFin = Date().addingTimeInterval(dur)
        let c = UNMutableNotificationContent(); c.title = "Jarvis"; c.body = "Temporizador terminado"; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "temporizador", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, dur), repeats: false)))
        disparo = Timer.scheduledTimer(withTimeInterval: dur, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.tempFin = nil
            for i in 0..<6 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8) { AudioServicesPlaySystemSound(1005) } }
        }
    }

    func cancelar() {
        disparo?.invalidate(); disparo = nil; tempFin = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["temporizador"])
    }
}

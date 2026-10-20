import Foundation
import UIKit
import UserNotifications

struct Linea: Identifiable { let id = UUID(); let yo: Bool; let texto: String }

@MainActor
final class Brain: ObservableObject {
    @Published var chat: [Linea] = []
    @Published var pensando = false
    var historial: [[String: Any]] = []
    let modelo = "claude-sonnet-5-5"

    var memoria: [String] {
        get { UserDefaults.standard.stringArray(forKey: "memoria") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "memoria") }
    }

    func sistema() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_ES"); f.dateFormat = "EEEE d 'de' MMMM 'de' yyyy, HH:mm"
        var s = "Eres Jarvis, el asistente personal de IA de Sergio, un founder y consultor de IA en Latinoamérica. Respondes siempre en español, conciso y directo, máximo tres oraciones salvo que pidan más. Tus respuestas se leen en voz alta: sin markdown, sin listas, sin emojis ni enlaces largos. Estás en su iPhone: puedes abrir apps y enlaces con la herramienta abrir_url (por ejemplo youtube.com/results?search_query=..., maps.apple.com/?q=..., spotify:search:..., tel:, sms:, shortcuts://run-workflow?name=...), programar recordatorios y guardar recuerdos. Para vídeos de YouTube abre la búsqueda. No puedes controlar el móvil más allá de eso. Ahora es " + f.string(from: Date()) + "."
        if !memoria.isEmpty { s += " Lo que recuerdas de Sergio: " + memoria.joined(separator: "; ") + "." }
        return s
    }

    func herramientas(busqueda: Bool) -> [[String: Any]] {
        var t: [[String: Any]] = [
            ["name": "abrir_url", "description": "Abre una URL o esquema de app en el iPhone (https, youtube, spotify, tel, sms, maps, shortcuts).",
             "input_schema": ["type": "object", "properties": ["url": ["type": "string"]], "required": ["url"]]],
            ["name": "recordatorio", "description": "Programa una notificación local de recordatorio.",
             "input_schema": ["type": "object", "properties": ["mensaje": ["type": "string"], "en_minutos": ["type": "number"]], "required": ["mensaje", "en_minutos"]]],
            ["name": "recordar", "description": "Guarda un dato de Sergio en la memoria de largo plazo.",
             "input_schema": ["type": "object", "properties": ["texto": ["type": "string"]], "required": ["texto"]]],
            ["name": "olvidar_todo", "description": "Borra toda la memoria de largo plazo.",
             "input_schema": ["type": "object", "properties": [:]]]
        ]
        if busqueda { t.append(["type": "web_search_20250305", "name": "web_search", "max_uses": 3]) }
        return t
    }

    func post(_ msgs: [[String: Any]], busqueda: Bool) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        r.httpMethod = "POST"
        r.timeoutInterval = 90
        r.setValue(Secrets.anthropic, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = ["model": modelo, "max_tokens": 1024, "system": sistema(), "tools": herramientas(busqueda: busqueda), "messages": msgs]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, resp) = try await URLSession.shared.data(for: r)
        let j = (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
            let m = ((j["error"] as? [String: Any])?["message"] as? String) ?? "error \(h.statusCode)"
            throw NSError(domain: "api", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey: m])
        }
        return j
    }

    func ejecutar(_ nombre: String, _ inp: [String: Any]) async -> String {
        switch nombre {
        case "abrir_url":
            guard let s = inp["url"] as? String else { return "falta url" }
            var u = URL(string: s)
            if u == nil || u?.scheme == nil { u = URL(string: "https://" + s) }
            guard let url = u else { return "url inválida" }
            let ok = await UIApplication.shared.open(url)
            return ok ? "abierto" : "no se pudo abrir"
        case "recordatorio":
            let m = inp["mensaje"] as? String ?? "Recordatorio"
            let mins = (inp["en_minutos"] as? Double) ?? Double(inp["en_minutos"] as? Int ?? 1)
            let c = UNMutableNotificationContent(); c.title = "Jarvis"; c.body = m; c.sound = .default
            let tr = UNTimeIntervalNotificationTrigger(timeInterval: max(1, mins * 60), repeats: false)
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: tr))
            return "recordatorio programado"
        case "recordar":
            if let t = inp["texto"] as? String { memoria.append(t) }
            return "guardado"
        case "olvidar_todo":
            memoria = []; return "memoria borrada"
        default: return "herramienta desconocida"
        }
    }

    func responder(_ texto: String) async -> String {
        pensando = true
        defer { pensando = false }
        var trabajo = historial
        trabajo.append(["role": "user", "content": texto])
        var busqueda = true
        var final = ""
        do {
            for _ in 0..<6 {
                let j: [String: Any]
                do { j = try await post(trabajo, busqueda: busqueda) }
                catch let e as NSError where busqueda && e.code == 400 { busqueda = false; j = try await post(trabajo, busqueda: false) }
                let c = (j["content"] as? [[String: Any]]) ?? []
                trabajo.append(["role": "assistant", "content": c])
                let usos = c.filter { ($0["type"] as? String) == "tool_use" }
                let txt = c.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }.joined(separator: " ")
                if usos.isEmpty {
                    if (j["stop_reason"] as? String) == "pause_turn" { continue }
                    final = txt; break
                }
                var res: [[String: Any]] = []
                for u in usos {
                    let r = await ejecutar(u["name"] as? String ?? "", (u["input"] as? [String: Any]) ?? [:])
                    res.append(["type": "tool_result", "tool_use_id": u["id"] as? String ?? "", "content": r])
                }
                trabajo.append(["role": "user", "content": res])
                final = txt
            }
        } catch {
            return "Error: " + error.localizedDescription
        }
        if final.isEmpty { final = "Hecho." }
        historial.append(["role": "user", "content": texto])
        historial.append(["role": "assistant", "content": final])
        if historial.count > 24 { historial.removeFirst(historial.count - 24) }
        return final
    }
}

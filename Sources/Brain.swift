import Foundation
import UIKit
import UserNotifications

struct Linea: Identifiable { let id = UUID(); let yo: Bool; let texto: String }

@MainActor
final class Brain: ObservableObject {
    @Published var chat: [Linea] = []
    @Published var pensando = false
    var historial: [[String: Any]] = []
    let modelo = "gemini-3.8-flash"

    var memoria: [String] {
        get { UserDefaults.standard.stringArray(forKey: "memoria") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "memoria") }
    }

    struct Habilidad: Codable { var nombre: String; var descripcion: String; var plantilla: String }
    var habLocales: [Habilidad] {
        get { (try? JSONDecoder().decode([Habilidad].self, from: UserDefaults.standard.data(forKey: "hab_local") ?? Data())) ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "hab_local") }
    }
    var cfg: [String: Any] {
        get { (try? JSONSerialization.jsonObject(with: UserDefaults.standard.data(forKey: "cfg") ?? Data()) as? [String: Any]) ?? [:] }
        set { UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: newValue), forKey: "cfg") }
    }
    var habRemotas: [Habilidad] {
        ((cfg["habilidades"] as? [[String: Any]]) ?? []).compactMap {
            guard let n = $0["nombre"] as? String, let t = $0["plantilla"] as? String else { return nil }
            return Habilidad(nombre: n, descripcion: ($0["descripcion"] as? String) ?? n, plantilla: t)
        }
    }
    var habilidades: [Habilidad] { habRemotas + habLocales }
    var sugerencias: [String] { (cfg["sugerencias"] as? [String]) ?? [] }
    var ultimaCfg = Date.distantPast

    func actualizarConfig() async {
        if Date().timeIntervalSince(ultimaCfg) < 60 { return }
        ultimaCfg = Date()
        guard let u = URL(string: "https://raw.githubusercontent.com/sergitronix/jarvis-iphone/main/config.json?t=\(Int(Date().timeIntervalSince1970))") else { return }
        var r = URLRequest(url: u); r.timeoutInterval = 8; r.cachePolicy = .reloadIgnoringLocalCacheData
        if let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { cfg = j }
    }

    func nomFn(_ n: String) -> String {
        "h_" + String(n.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }

    func sistema() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_ES"); f.dateFormat = "EEEE d 'de' MMMM 'de' yyyy, HH:mm"
        var s = "Eres Jarvis, el asistente personal de IA de Sergio, un founder y consultor de IA en Latinoamérica. Respondes siempre en español, conciso y directo, máximo tres oraciones salvo que pidan más. Tus respuestas se leen en voz alta: sin markdown, sin listas, sin emojis ni enlaces largos. Estás en su iPhone: puedes abrir apps y enlaces con la herramienta abrir_url (por ejemplo youtube.com/results?search_query=..., maps.apple.com/?q=..., spotify:search:..., tel:, sms:, shortcuts://run-workflow?name=...), programar recordatorios y guardar recuerdos. Para vídeos de YouTube abre la búsqueda. No puedes controlar el móvil más allá de eso. Ahora es " + f.string(from: Date()) + "."
        if let e = cfg["prompt_extra"] as? String, !e.isEmpty { s += " " + e }
        if !habilidades.isEmpty { s += " Tienes habilidades extra instaladas, úsalas cuando encajen: " + habilidades.map { $0.nombre + " (" + $0.descripcion + ")" }.joined(separator: "; ") + ". Si Sergio te pide una función nueva que se pueda hacer abriendo una URL o esquema de app con un texto variable, usa crear_habilidad con una plantilla que contenga {q}." }
        if !memoria.isEmpty { s += " Lo que recuerdas de Sergio: " + memoria.joined(separator: "; ") + "." }
        return s
    }

    func herramientas() -> [[String: Any]] {
        var extra: [[String: Any]] = habilidades.map {
            ["name": nomFn($0.nombre), "description": $0.descripcion + ". Abre: " + $0.plantilla,
             "parameters": ["type": "OBJECT", "properties": ["q": ["type": "STRING", "description": "texto que sustituye {q}"]]]]
        }
        extra.append(["name": "crear_habilidad", "description": "Crea una habilidad nueva y permanente que abre una URL o esquema de app. La plantilla usa {q} para el texto variable, por ejemplo https://www.google.com/search?q={q}.",
                      "parameters": ["type": "OBJECT", "properties": ["nombre": ["type": "STRING"], "descripcion": ["type": "STRING"], "plantilla": ["type": "STRING"]], "required": ["nombre", "descripcion", "plantilla"]]])
        extra.append(["name": "borrar_habilidad", "description": "Borra una habilidad creada por el usuario.",
                      "parameters": ["type": "OBJECT", "properties": ["nombre": ["type": "STRING"]], "required": ["nombre"]]])
        return [["functionDeclarations": extra + [
            ["name": "abrir_url", "description": "Abre una URL o esquema de app en el iPhone (https, youtube, spotify, tel, sms, maps, shortcuts).",
             "parameters": ["type": "OBJECT", "properties": ["url": ["type": "STRING"]], "required": ["url"]]],
            ["name": "recordatorio", "description": "Programa una notificación local de recordatorio.",
             "parameters": ["type": "OBJECT", "properties": ["mensaje": ["type": "STRING"], "en_minutos": ["type": "NUMBER"]], "required": ["mensaje", "en_minutos"]]],
            ["name": "recordar", "description": "Guarda un dato de Sergio en la memoria de largo plazo.",
             "parameters": ["type": "OBJECT", "properties": ["texto": ["type": "STRING"]], "required": ["texto"]]],
            ["name": "olvidar_todo", "description": "Borra toda la memoria de largo plazo."]
        ]]]
    }

    let modelos = ["gemini-3.1-flash-lite", "gemini-3.5-flash-lite", "gemini-flash-lite-latest", "gemini-3.8-flash"]

    func post(_ contenido: [[String: Any]]) async throws -> [String: Any] {
        let body: [String: Any] = ["systemInstruction": ["parts": [["text": sistema()]]], "contents": contenido, "tools": herramientas()]
        let datos = try JSONSerialization.data(withJSONObject: body)
        var ultimo = "sin respuesta"
        for m in modelos {
            var url = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(m):generateContent")!)
            url.httpMethod = "POST"
            url.timeoutInterval = m.contains("lite") ? 8 : 25
            url.setValue(Secrets.gemini, forHTTPHeaderField: "x-goog-api-key")
            url.setValue("application/json", forHTTPHeaderField: "content-type")
            url.httpBody = datos
            do {
                let (d, resp) = try await URLSession.shared.data(for: url)
                let j = (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code < 400 { return j }
                ultimo = ((j["error"] as? [String: Any])?["message"] as? String) ?? "error \(code)"
            } catch {
                ultimo = error.localizedDescription
            }
        }
        throw NSError(domain: "api", code: 1, userInfo: [NSLocalizedDescriptionKey: ultimo])
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
        case "crear_habilidad":
            guard let n = inp["nombre"] as? String, let t = inp["plantilla"] as? String else { return "faltan datos" }
            var l = habLocales.filter { $0.nombre != n }
            l.append(Habilidad(nombre: n, descripcion: (inp["descripcion"] as? String) ?? n, plantilla: t))
            habLocales = l
            return "habilidad creada"
        case "borrar_habilidad":
            let n = inp["nombre"] as? String ?? ""
            habLocales = habLocales.filter { $0.nombre != n }
            return "borrada"
        default:
            if let h = habilidades.first(where: { nomFn($0.nombre) == nombre }) {
                let q = (inp["q"] as? String) ?? ""
                let cod = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
                return await ejecutar("abrir_url", ["url": h.plantilla.replacingOccurrences(of: "{q}", with: cod)])
            }
            return "herramienta desconocida"
        }
    }

    func responder(_ texto: String) async -> String {
        pensando = true
        defer { pensando = false }
        await actualizarConfig()
        var trabajo = historial
        trabajo.append(["role": "user", "parts": [["text": texto]]])
        var final = ""
        do {
            for _ in 0..<6 {
                let j = try await post(trabajo)
                guard let cand = (j["candidates"] as? [[String: Any]])?.first,
                      let cont = cand["content"] as? [String: Any],
                      let partes = cont["parts"] as? [[String: Any]] else { final = "No obtuve respuesta."; break }
                trabajo.append(["role": "model", "parts": partes])
                let txt = partes.compactMap { $0["text"] as? String }.joined(separator: " ")
                let llamadas = partes.compactMap { $0["functionCall"] as? [String: Any] }
                if llamadas.isEmpty { final = txt; break }
                var resp: [[String: Any]] = []
                for c in llamadas {
                    let n = c["name"] as? String ?? ""
                    let r = await ejecutar(n, (c["args"] as? [String: Any]) ?? [:])
                    resp.append(["functionResponse": ["name": n, "response": ["result": r]]])
                }
                trabajo.append(["role": "user", "parts": resp])
                final = txt
            }
        } catch {
            return "Error: " + error.localizedDescription
        }
        if final.isEmpty { final = "Hecho." }
        historial.append(["role": "user", "parts": [["text": texto]]])
        historial.append(["role": "model", "parts": [["text": final]]])
        if historial.count > 24 { historial.removeFirst(historial.count - 24) }
        return final
    }
}

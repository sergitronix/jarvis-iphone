import Foundation
import UIKit

enum Registro {
    static var buffer: [String] = []
    static var subiendo = false
    static let repo = "https://api.github.com/repos/sergitronix/jarvis-datos/contents/"

    static func add(_ s: String) {
        let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm:ss"
        buffer.append(f.string(from: Date()) + " " + s)
        if buffer.count > 200 { buffer.removeFirst(buffer.count - 200) }
    }

    static func req(_ ruta: String, _ metodo: String, _ cuerpo: Data? = nil) -> URLRequest {
        var r = URLRequest(url: URL(string: repo + ruta)!)
        r.httpMethod = metodo; r.timeoutInterval = 15
        r.setValue("token " + Secrets.log, forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.httpBody = cuerpo
        return r
    }

    // Devuelve (texto, sha) de un archivo del repo privado de datos.
    static func bajar(_ nombre: String) async -> (String, String?)? {
        guard !Secrets.log.isEmpty, let (d, _) = try? await URLSession.shared.data(for: req(nombre, "GET")),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let sha = j["sha"] as? String
        guard let c = (j["content"] as? String)?.replacingOccurrences(of: "\n", with: ""),
              let dd = Data(base64Encoded: c), let t = String(data: dd, encoding: .utf8) else { return nil }
        return (t, sha)
    }

    static func guardar(_ nombre: String, _ texto: String) async {
        guard !Secrets.log.isEmpty else { return }
        var cuerpo: [String: Any] = ["message": "movil", "content": Data(texto.utf8).base64EncodedString()]
        if let (_, sha) = await bajar(nombre), let s = sha { cuerpo["sha"] = s }
        _ = try? await URLSession.shared.data(for: req(nombre, "PUT", try? JSONSerialization.data(withJSONObject: cuerpo)))
    }

    static func subir() async {
        if subiendo || buffer.isEmpty { return }
        subiendo = true; defer { subiendo = false }
        let envio = buffer
        let previo = (await bajar("movil.log"))?.0 ?? ""
        var lineas = previo.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("[") } + envio
        if lineas.count > 400 { lineas.removeFirst(lineas.count - 400) }
        let texto = "[" + UIDevice.current.name + " iOS " + UIDevice.current.systemVersion + "]\n" + lineas.joined(separator: "\n")
        await guardar("movil.log", texto)
        buffer.removeAll { envio.contains($0) }
    }
}

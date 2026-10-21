import Foundation
import UIKit

enum Registro {
    static var buffer: [String] = []
    static var subiendo = false
    static func add(_ s: String) {
        let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm:ss"
        buffer.append(f.string(from: Date()) + " " + s)
        if buffer.count > 200 { buffer.removeFirst(buffer.count - 200) }
    }
    static func subir() async {
        if subiendo || buffer.isEmpty || Secrets.log.isEmpty { return }
        subiendo = true; defer { subiendo = false }
        let envio = buffer
        let base = "https://api.github.com/repos/sergitronix/jarvis-iphone/contents/movil.log"
        func req(_ url: String, _ metodo: String, _ cuerpo: Data? = nil) -> URLRequest {
            var r = URLRequest(url: URL(string: url)!)
            r.httpMethod = metodo; r.timeoutInterval = 15
            r.setValue("token " + Secrets.log, forHTTPHeaderField: "Authorization")
            r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            r.httpBody = cuerpo
            return r
        }
        var sha: String? = nil
        var previo = ""
        if let (d, _) = try? await URLSession.shared.data(for: req(base + "?ref=logs", "GET")),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            sha = j["sha"] as? String
            if let c = (j["content"] as? String)?.replacingOccurrences(of: "\n", with: ""),
               let dd = Data(base64Encoded: c), let t = String(data: dd, encoding: .utf8) { previo = t }
        }
        var lineas = previo.split(separator: "\n").map(String.init) + envio
        if lineas.count > 400 { lineas.removeFirst(lineas.count - 400) }
        let texto = "[" + UIDevice.current.name + " iOS " + UIDevice.current.systemVersion + "]\n" + lineas.filter { !$0.hasPrefix("[") }.joined(separator: "\n")
        var cuerpo: [String: Any] = ["message": "log", "content": Data(texto.utf8).base64EncodedString(), "branch": "logs"]
        if let s = sha { cuerpo["sha"] = s }
        if let (_, resp) = try? await URLSession.shared.data(for: req(base, "PUT", try? JSONSerialization.data(withJSONObject: cuerpo))),
           (resp as? HTTPURLResponse)?.statusCode ?? 0 < 300 { buffer.removeAll { envio.contains($0) } }
    }
}

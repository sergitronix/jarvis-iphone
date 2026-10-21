
import Foundation
import CryptoKit

enum EdgeTTS {
    static let token = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"

    static func gec() -> String {
        var t = Date().timeIntervalSince1970 + 11644473600
        t -= t.truncatingRemainder(dividingBy: 300)
        let ticks = UInt64(t * 10_000_000)
        let h = SHA256.hash(data: Data("\(ticks)\(token)".utf8))
        return h.map { String(format: "%02X", $0) }.joined()
    }

    static func escapar(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func sintetizar(_ texto: String, voz: String = "es-MX-JorgeNeural") async -> Data? {
        let cid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        guard let url = URL(string: "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=\(token)&Sec-MS-GEC=\(gec())&Sec-MS-GEC-Version=1-130.0.2849.68&ConnectionId=\(cid)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0", forHTTPHeaderField: "User-Agent")
        let ws = URLSession.shared.webSocketTask(with: req)
        ws.resume()
        let corte = Task { try? await Task.sleep(nanoseconds: 12_000_000_000); ws.cancel(with: .goingAway, reason: nil) }
        defer { corte.cancel(); ws.cancel(with: .normalClosure, reason: nil) }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss"
        let ts = f.string(from: Date()) + " GMT+0000 (Coordinated Universal Time)"
        let cfg = "X-Timestamp:\(ts)\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n"
        let rid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let ssml = "X-RequestId:\(rid)\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:\(ts)Z\r\nPath:ssml\r\n\r\n<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='es-MX'><voice name='\(voz)'><prosody pitch='+0Hz' rate='+0%' volume='+0%'>\(escapar(texto))</prosody></voice></speak>"
        do {
            try await ws.send(.string(cfg))
            try await ws.send(.string(ssml))
            var audio = Data()
            while true {
                let m = try await ws.receive()
                switch m {
                case .string(let s):
                    if s.contains("Path:turn.end") { return audio.isEmpty ? nil : audio }
                case .data(let d):
                    if d.count > 2 {
                        let n = Int(d[0]) << 8 | Int(d[1])
                        if d.count >= 2 + n, String(decoding: d[2..<(2 + n)], as: UTF8.self).contains("Path:audio") { audio.append(d.subdata(in: (2 + n)..<d.count)) }
                    }
                @unknown default: break
                }
            }
        } catch {
            return audio_vacio
        }
    }
    static let audio_vacio: Data? = nil
}

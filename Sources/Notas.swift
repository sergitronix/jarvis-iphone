import Foundation

enum Notas {
    static let clave = "notas_jarvis"
    static var todas: [String] {
        get { UserDefaults.standard.stringArray(forKey: clave) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: clave) }
    }
    static func plano(_ t: String) -> String {
        t.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
    }
    static func procesar(_ texto: String) -> String? {
        let s = plano(texto).trimmingCharacters(in: .whitespacesAndNewlines)
        for p in ["apunta que ", "apunta ", "anota que ", "anota ", "toma nota de ", "toma nota ", "guarda la nota "] {
            if s.hasPrefix(p) {
                let c = String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
                if c.isEmpty { return "¿Qué quieres que apunte?" }
                var n = todas; n.append(c); todas = n
                return "Apuntado. Tienes \(n.count) nota\(n.count == 1 ? "" : "s")."
            }
        }
        if s.contains("borra mis notas") || s.contains("borra las notas") || s.contains("borrar notas") {
            todas = []; return "Notas borradas."
        }
        if s.contains("mis notas") || s.contains("lee las notas") || s.contains("que tengo apuntado") {
            let n = todas
            if n.isEmpty { return "No tienes notas." }
            return "Tus notas: " + n.enumerated().map { "\($0.offset + 1), \($0.element)" }.joined(separator: ". ") + "."
        }
        return nil
    }
}

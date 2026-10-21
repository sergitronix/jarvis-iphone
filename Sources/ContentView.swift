import SwiftUI
import UserNotifications

let CIAN = Color(red: 0.30, green: 0.90, blue: 1.0)
let ORO = Color(red: 1.0, green: 0.68, blue: 0.22)
let FONDO = Color(red: 0.015, green: 0.03, blue: 0.06)

struct Esquinas: Shape {
    var l: CGFloat = 12
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

struct Rejilla: View {
    var body: some View {
        Canvas { g, s in
            var p = Path()
            var x: CGFloat = 0
            while x < s.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: s.height)); x += 32 }
            var y: CGFloat = 0
            while y < s.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: s.width, y: y)); y += 32 }
            g.stroke(p, with: .color(CIAN.opacity(0.045)), lineWidth: 0.5)
        }
    }
}

struct Reactor: View {
    var estado: Int  // 0 espera, 1 escuchando, 2 pensando, 3 hablando
    var nivel: Double = 0
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let m = min(size.width, size.height) / 2
                let vel: Double = estado == 0 ? 0.35 : (estado == 2 ? 2.6 : (estado == 1 ? 1.1 + nivel * 2 : 1.5))
                let pulso = estado == 1 ? min(1, 0.3 + nivel * 2.5) : (estado == 3 ? 0.5 + 0.5 * sin(t * 7) * sin(t * 2.3 + 1) : 0.5 + 0.5 * sin(t * (estado == 0 ? 1.4 : 5)))
                let col = estado == 1 ? ORO : CIAN
                // halo
                let halo = Path(ellipseIn: CGRect(x: c.x - m, y: c.y - m, width: m * 2, height: m * 2))
                g.fill(halo, with: .radialGradient(Gradient(colors: [col.opacity(0.28 + 0.15 * pulso), .clear]), center: c, startRadius: 0, endRadius: m))
                // ondas
                if estado != 0 {
                    for i in 0..<3 {
                        let ph = (t * (estado == 2 ? 0.5 : 0.45) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        let rr = m * CGFloat(0.25 + ph * 0.75 * (estado == 1 ? 0.8 + nivel : 1))
                        g.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                                 with: .color(col.opacity((1 - ph) * (estado == 1 ? 0.55 + 0.4 * nivel : 0.4))), lineWidth: estado == 1 ? 3 : 2)
                    }
                }
                // marcas
                var marcas = Path()
                for i in 0..<72 {
                    let a = Double(i) / 72 * 2 * .pi + t * 0.15 * vel
                    let r1 = m * 0.93, r2 = m * (i % 6 == 0 ? 0.84 : 0.89)
                    marcas.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * r1, y: c.y + CGFloat(sin(a)) * r1))
                    marcas.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r2, y: c.y + CGFloat(sin(a)) * r2))
                }
                g.stroke(marcas, with: .color(CIAN.opacity(0.55)), lineWidth: 1)
                // anillos con arcos
                let radios: [CGFloat] = [0.76, 0.62, 0.48, 0.34]
                for (i, f) in radios.enumerated() {
                    let r = m * f
                    let dir: Double = i % 2 == 0 ? 1 : -1
                    let ini = t * dir * vel * (0.5 + 0.35 * Double(i))
                    var a1 = Path()
                    a1.addArc(center: c, radius: r, startAngle: .radians(ini), endAngle: .radians(ini + 2.4), clockwise: false)
                    g.stroke(a1, with: .color(CIAN.opacity(0.5 + 0.4 * pulso)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    var a2 = Path()
                    a2.addArc(center: c, radius: r, startAngle: .radians(ini + 3.3), endAngle: .radians(ini + 4.6), clockwise: false)
                    g.stroke(a2, with: .color(ORO.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    g.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(CIAN.opacity(0.12)), lineWidth: 0.8)
                }
                // satélites
                for i in 0..<3 {
                    let a = t * vel * 1.4 + Double(i) * 2.094
                    let r = m * 0.76
                    let p = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
                    g.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(ORO))
                }
                // núcleo
                let rc = m * (0.19 + 0.03 * pulso)
                g.fill(Path(ellipseIn: CGRect(x: c.x - rc * 1.8, y: c.y - rc * 1.8, width: rc * 3.6, height: rc * 3.6)),
                       with: .radialGradient(Gradient(colors: [ORO.opacity(0.6), .clear]), center: c, startRadius: 0, endRadius: rc * 1.8))
                g.fill(Path(ellipseIn: CGRect(x: c.x - rc, y: c.y - rc, width: rc * 2, height: rc * 2)),
                       with: .radialGradient(Gradient(colors: [.white, ORO, ORO.opacity(0.7)]), center: c, startRadius: 0, endRadius: rc))
            }
        }
    }
}

struct FondoEstatico: View {
    var body: some View {
        Canvas { g, s in
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let m = min(s.width, s.height) / 2
            for f in [0.95, 0.8, 0.65, 0.5, 0.35] as [CGFloat] {
                g.stroke(Path(ellipseIn: CGRect(x: c.x - m * f, y: c.y - m * f, width: m * f * 2, height: m * f * 2)), with: .color(CIAN.opacity(0.05)), lineWidth: 1)
            }
            var p = Path()
            for i in 0..<120 {
                let a = Double(i) / 120 * 2 * .pi
                let r2 = m * (i % 5 == 0 ? 0.9 : 0.93)
                p.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * m * 0.96, y: c.y + CGFloat(sin(a)) * m * 0.96))
                p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r2, y: c.y + CGFloat(sin(a)) * r2))
            }
            g.stroke(p, with: .color(CIAN.opacity(0.07)), lineWidth: 1)
        }.drawingGroup()
    }
}

struct Burbuja: View {
    let l: Linea
    var body: some View {
        let col = l.yo ? ORO : CIAN
        Text(l.texto)
            .font(.system(size: 15, design: .rounded)).foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(col.opacity(0.08))
            .overlay(Rectangle().stroke(col.opacity(0.25), lineWidth: 0.5))
            .overlay(Esquinas(l: 9).stroke(col, lineWidth: 1.5))
            .frame(maxWidth: .infinity, alignment: l.yo ? .trailing : .leading)
            .padding(l.yo ? .leading : .trailing, 40)
    }
}

struct ContentView: View {
    @StateObject var brain = Brain()
    @StateObject var voz = Voz()
    @StateObject var reloj = Reloj()
    @State var texto = ""
    @State var mostrarCam = false
    @State var camAuto = false
    @State var camPregunta = ""
    @State var mostrarMapa = false
    @State var mapaConsulta = ""
    @Environment(\.scenePhase) var fase

    var estado: Int { (voz.oyendo || voz.activo) ? 1 : (brain.pensando ? 2 : (voz.hablando ? 3 : 0)) }
    var nombre: String { ["EN ESPERA", "ESCUCHANDO", "PENSANDO", "HABLANDO"][estado] }

    var body: some View {
        ZStack {
            FONDO.ignoresSafeArea()
            Rejilla().ignoresSafeArea()
            GeometryReader { g in
                FondoEstatico().opacity(0.9)
                    .frame(width: g.size.width * 1.9, height: g.size.width * 1.9)
                    .position(x: g.size.width / 2, y: g.size.height * 0.36)
            }.ignoresSafeArea().allowsHitTesting(false)
            RadialGradient(colors: [.clear, FONDO.opacity(0.85)], center: .center, startRadius: 150, endRadius: 520).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("J A R V I S").font(.system(size: 20, weight: .light, design: .monospaced)).foregroundColor(CIAN)
                        Text("ASISTENTE PERSONAL  ·  V1.0").font(.system(size: 9, design: .monospaced)).foregroundColor(CIAN.opacity(0.5))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        TimelineView(.periodic(from: .now, by: 1)) { tl in
                            Text(tl.date, format: .dateTime.hour().minute()).font(.system(size: 20, weight: .light, design: .monospaced)).foregroundColor(.white)
                        }
                        Text(nombre).font(.system(size: 10, design: .monospaced)).foregroundColor(estado == 0 ? CIAN.opacity(0.6) : ORO)
                            .padding(.horizontal, 8).padding(.vertical, 2).overlay(Esquinas(l: 5).stroke(estado == 0 ? CIAN.opacity(0.6) : ORO, lineWidth: 1))
                    }
                }.padding(.horizontal, 18).padding(.top, 6)

                TimelineView(.periodic(from: .now, by: 0.1)) { tl in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tl.date, format: .dateTime.weekday(.wide).day().month(.wide)).font(.system(size: 10, design: .monospaced)).foregroundColor(CIAN.opacity(0.7))
                            if reloj.cronoCorre || reloj.cronoAcum > 0 {
                                Text("CRONO " + reloj.cronoTexto(tl.date)).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(ORO)
                            }
                        }
                        Spacer()
                        if let r = reloj.tempRestante(tl.date) {
                            Text("TEMP " + Reloj.fmt(r.rounded(.up), dec: false)).font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(r < 10 ? .red : CIAN)
                        }
                    }.padding(.horizontal, 20)
                }
                ZStack {
                    Reactor(estado: estado, nivel: voz.nivel).drawingGroup().opacity(estado == 0 ? 0.7 : 1).animation(.easeInOut(duration: 0.4), value: estado)
                    ForEach(0..<4, id: \.self) { i in
                        Esquinas(l: 16).stroke(CIAN.opacity(0.7), lineWidth: 1.5).frame(width: 300, height: 300)
                            .rotationEffect(.degrees(Double(i) * 90))
                    }.opacity(0.0)
                    VStack { Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(estado == 1 ? ORO : (estado == 0 ? CIAN.opacity(0.4) : CIAN)).frame(width: 7, height: 7)
                            Text(estado == 1 ? "ESCUCHANDO" : (estado == 2 ? "PENSANDO" : (estado == 3 ? "HABLANDO · TOCA PARA CALLAR" : (voz.manosLibres ? "EN ESPERA · DI «JARVIS»" : "TOCA PARA HABLAR"))))
                                .font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(2)
                                .foregroundColor(estado == 1 ? ORO : CIAN.opacity(estado == 0 ? 0.6 : 1))
                        }.padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(Esquinas(l: 6).stroke(estado == 1 ? ORO : CIAN.opacity(0.6), lineWidth: 1))
                    }
                }
                .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit).padding(.horizontal, 8).layoutPriority(0)
                    .onTapGesture { if voz.hablando { voz.callar() } else { voz.escuchar() } }

                ScrollViewReader { sv in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            if brain.chat.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(brain.sugerencias.isEmpty ? ["Pon un vídeo de gatos en YouTube", "Recuérdame en 10 minutos beber agua", "Llévame a casa en Maps"] : brain.sugerencias, id: \.self) { s in
                                        Button(action: { enviar(s) }) {
                                            Text(s).font(.system(size: 13, design: .monospaced)).foregroundColor(CIAN)
                                                .frame(maxWidth: .infinity).padding(10).overlay(Esquinas(l: 8).stroke(CIAN.opacity(0.7), lineWidth: 1))
                                        }
                                    }
                                }.padding(.top, 8)
                            }
                            ForEach(brain.chat) { l in Burbuja(l: l).id(l.id) }
                            if voz.oyendo && !voz.parcial.isEmpty {
                                Text(voz.parcial).font(.system(size: 15, design: .rounded)).foregroundColor(ORO.opacity(0.8)).frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            if brain.pensando { Text("Procesando...").font(.system(size: 12, design: .monospaced)).foregroundColor(CIAN.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading) }
                        }.padding(.horizontal, 16)
                    }
                    .onChange(of: fase) { f in voz.cambioFase(f == .active) }
                    .onChange(of: brain.pensando) { p in voz.bloqueado = p }
                    .onChange(of: brain.chat.count) { _ in if let u = brain.chat.last { withAnimation { sv.scrollTo(u.id, anchor: .bottom) } } }
                }
                .padding(.vertical, 8)
                .background(CIAN.opacity(0.04))
                .overlay(Esquinas(l: 14).stroke(CIAN.opacity(0.8), lineWidth: 1.5))
                .overlay(Rectangle().stroke(CIAN.opacity(0.15), lineWidth: 0.5))
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
                .padding(.horizontal, 12).frame(minHeight: 120)

                HStack(spacing: 10) {
                    TextField("Escribe una orden...", text: $texto)
                        .padding(10).foregroundColor(.white)
                        .background(CIAN.opacity(0.07)).overlay(Esquinas(l: 8).stroke(CIAN.opacity(0.7), lineWidth: 1))
                        .submitLabel(.send).onSubmit { enviarTexto() }
                    Button(action: {
                        camAuto = false
                        camPregunta = texto.trimmingCharacters(in: .whitespaces).isEmpty ? "¿Qué ves? Descríbelo en pocas frases." : texto
                        texto = ""
                        mostrarCam = true
                    }) {
                        Image(systemName: "camera.fill").font(.system(size: 17)).foregroundColor(CIAN)
                            .frame(width: 38, height: 38).background(Circle().fill(CIAN.opacity(0.1)))
                            .overlay(Circle().stroke(CIAN.opacity(0.6), lineWidth: 1.5))
                    }
                    Button(action: { mapaConsulta = ""; mostrarMapa = true }) {
                        Image(systemName: "map.fill").font(.system(size: 17)).foregroundColor(CIAN)
                            .frame(width: 38, height: 38).background(Circle().fill(CIAN.opacity(0.1)))
                            .overlay(Circle().stroke(CIAN.opacity(0.6), lineWidth: 1.5))
                    }
                    Button(action: {
                        voz.segundoPlano.toggle()
                        brain.chat.append(Linea(yo: false, texto: voz.segundoPlano ? "Segundo plano activado: sigo escuchando con la pantalla bloqueada." : "Segundo plano desactivado: dejo de escuchar al salir de la app."))
                    }) {
                        Image(systemName: voz.segundoPlano ? "moon.fill" : "moon").font(.system(size: 17))
                            .foregroundColor(voz.segundoPlano ? .black : CIAN)
                            .frame(width: 38, height: 38).background(Circle().fill(voz.segundoPlano ? ORO : CIAN.opacity(0.1)))
                            .overlay(Circle().stroke(voz.segundoPlano ? ORO : CIAN.opacity(0.6), lineWidth: 1.5))
                    }
                    Button(action: { voz.alternarManos() }) {
                        Image(systemName: voz.manosLibres ? "ear.fill" : "ear").font(.system(size: 17))
                            .foregroundColor(voz.manosLibres ? .black : CIAN)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(voz.manosLibres ? ORO : CIAN.opacity(0.1)))
                            .overlay(Circle().stroke(voz.manosLibres ? ORO : CIAN.opacity(0.6), lineWidth: 1.5))
                    }
                    Button(action: { if voz.hablando { voz.callar() } else { voz.escuchar() } }) {
                        ZStack {
                            Circle().fill(voz.oyendo ? ORO : CIAN.opacity(0.9)).frame(width: 54, height: 54)
                            Circle().stroke((voz.oyendo ? ORO : CIAN).opacity(0.5), lineWidth: 2).frame(width: 64, height: 64)
                            Image(systemName: voz.hablando ? "speaker.slash.fill" : (voz.oyendo ? "waveform" : "mic.fill")).font(.system(size: 22)).foregroundColor(.black)
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .fullScreenCover(isPresented: $mostrarCam) {
            CamaraSheet(auto: camAuto, onFoto: { d in enviarFoto(d, camPregunta) }, onCerrar: { mostrarCam = false })
        }
        .fullScreenCover(isPresented: $mostrarMapa) {
            MapaHolo(consulta: mapaConsulta, onCerrar: { mostrarMapa = false })
        }
        .onChange(of: brain.mapaPedido) { q in
            if let q = q { mapaConsulta = q; mostrarMapa = true; brain.mapaPedido = nil }
        }
        .onAppear {
            voz.permisos()
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            voz.onFinal = { t in enviar(t) }
            Task { await brain.actualizarConfig() }
        }
    }

    func enviarTexto() {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        texto = ""
        enviar(t)
    }

    func enviarFoto(_ d: Data, _ pregunta: String) {
        brain.chat.append(Linea(yo: true, texto: "📷 " + pregunta))
        Task {
            var r = await brain.responder(pregunta + " (Responde en pocas frases, para leerlo en voz alta.)", imagen: d)
            if r.hasPrefix("Error:") { r = "No pude analizar la foto, prueba otra vez." }
            brain.chat.append(Linea(yo: false, texto: r))
            voz.hablar(r)
        }
    }

    func enviar(_ t: String) {
        brain.chat.append(Linea(yo: true, texto: t))
        let pl = t.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        if ["mira esto", "mira esta", "mira eso", "que es esto", "que ves", "que estoy viendo", "lee esto", "identifica esto", "dime que es"].contains(where: { pl.contains($0) }) {
            camPregunta = t; camAuto = true; mostrarCam = true
            return
        }
        if let r = reloj.procesar(t) {
            brain.chat.append(Linea(yo: false, texto: r))
            voz.hablar(r)
            return
        }
        Task {
            var r = await brain.responder(t)
            if r.hasPrefix("Error:") { r = "No pude conectar con el cerebro, prueba otra vez en unos segundos." }
            brain.chat.append(Linea(yo: false, texto: r))
            voz.hablar(r)
        }
    }
}

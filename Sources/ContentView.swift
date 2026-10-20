import SwiftUI
import UserNotifications

struct Reactor: View {
    var activo: Bool
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let cian = Color(red: 0.3, green: 0.9, blue: 1)
                let pulso = activo ? 0.5 + 0.5 * sin(t * 5) : 0.5 + 0.5 * sin(t * 1.5)
                for i in 0..<4 {
                    let r = size.width * (0.18 + 0.1 * CGFloat(i))
                    var p = Path()
                    let ini = t * (i % 2 == 0 ? 1 : -1) * (0.6 + 0.3 * Double(i))
                    p.addArc(center: c, radius: r, startAngle: .radians(ini), endAngle: .radians(ini + 4.2), clockwise: false)
                    g.stroke(p, with: .color(cian.opacity(0.35 + 0.4 * pulso)), style: StrokeStyle(lineWidth: 2 + CGFloat(i), lineCap: .round))
                }
                let rc = size.width * (0.08 + 0.02 * pulso)
                g.fill(Path(ellipseIn: CGRect(x: c.x - rc, y: c.y - rc, width: rc * 2, height: rc * 2)), with: .color(cian.opacity(0.8)))
            }
        }
    }
}

struct ContentView: View {
    @StateObject var brain = Brain()
    @StateObject var voz = Voz()
    @State var texto = ""
    let cian = Color(red: 0.3, green: 0.9, blue: 1)

    var estado: String {
        if voz.oyendo { return "ESCUCHANDO" }
        if brain.pensando { return "PENSANDO" }
        if voz.hablando { return "HABLANDO" }
        return "EN ESPERA"
    }

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.04, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 8) {
                HStack {
                    Text("J A R V I S").font(.system(size: 18, weight: .light, design: .monospaced)).foregroundColor(cian)
                    Spacer()
                    Text(estado).font(.system(size: 12, design: .monospaced)).foregroundColor(.orange)
                }.padding(.horizontal)
                Reactor(activo: voz.oyendo || voz.hablando || brain.pensando).frame(height: 220)
                ScrollViewReader { sv in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(brain.chat) { l in
                                Text(l.texto).font(.system(size: 15)).foregroundColor(.white)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).stroke(l.yo ? Color.orange : cian, lineWidth: 1).background(Color.black.opacity(0.3)))
                                    .frame(maxWidth: .infinity, alignment: l.yo ? .trailing : .leading)
                                    .id(l.id)
                            }
                            if voz.oyendo && !voz.parcial.isEmpty {
                                Text(voz.parcial).font(.system(size: 15)).foregroundColor(.orange).frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }.padding(.horizontal)
                    }
                    .onChange(of: brain.chat.count) { _ in if let u = brain.chat.last { withAnimation { sv.scrollTo(u.id, anchor: .bottom) } } }
                }
                HStack {
                    TextField("Escribe...", text: $texto).textFieldStyle(.roundedBorder).submitLabel(.send).onSubmit { enviarTexto() }
                    Button(action: { if voz.hablando { voz.callar() } else { voz.escuchar() } }) {
                        Image(systemName: voz.oyendo ? "waveform" : "mic.fill").font(.system(size: 22)).foregroundColor(.black)
                            .frame(width: 52, height: 52).background(Circle().fill(voz.oyendo ? Color.orange : cian))
                    }
                }.padding(.horizontal).padding(.bottom, 6)
            }
        }
        .onAppear {
            voz.permisos()
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            voz.onFinal = { t in enviar(t) }
        }
    }

    func enviarTexto() {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        texto = ""
        enviar(t)
    }

    func enviar(_ t: String) {
        brain.chat.append(Linea(yo: true, texto: t))
        Task {
            let r = await brain.responder(t)
            brain.chat.append(Linea(yo: false, texto: r))
            voz.hablar(r)
        }
    }
}

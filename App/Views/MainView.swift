import SwiftUI
import UIKit

enum CoroStyle {
    static let accent = Color(red: 1, green: 0.47, blue: 0.34)
    static let background = Color(red: 0.055, green: 0.065, blue: 0.08)
    static let card = Color(red: 0.09, green: 0.105, blue: 0.13)
}

struct MainView: View {
    @ObservedObject var session: SessionController
    @ObservedObject var auth: SpotifyAuth
    @State private var settings = false
    @StateObject private var blackScreen = BlackScreenController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if blackScreen.isEnabled {
                BlackScreenView(onExit: blackScreen.disable)
            } else {
                mainContent
            }
        }
        .statusBarHidden(blackScreen.isEnabled)
        .persistentSystemOverlays(blackScreen.isEnabled ? .hidden : .automatic)
        .sheet(isPresented: $settings) { SettingsView(session: session, auth: auth) }
        .sheet(item: $auth.page, onDismiss: { auth.dismissAuthorization() }) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
        .onChange(of: session.running) { _, running in
            if !running { blackScreen.disable() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { blackScreen.disable() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Restore immediately, including before a manual lock or app switch.
            blackScreen.disable()
        }
        .onDisappear { blackScreen.disable() }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coro").font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("LETRAS A TU RITMO").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { settings = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.title3).frame(width: 48, height: 48)
                            .background(CoroStyle.card, in: Circle())
                    }
                    .accessibilityLabel("Ajustes")
                    .disabled(auth.isAuthorizing || session.starting)
                }

                HStack(spacing: 8) {
                    Circle().fill(session.isDemo ? .orange : (session.running ? CoroStyle.accent : .gray)).frame(width: 7, height: 7)
                    Text(session.isDemo && session.running ? "DEMOSTRACIÓN" : (session.running ? "SESIÓN ACTIVA" : "LISTO CUANDO TÚ QUIERAS"))
                        .font(.caption.weight(.semibold)).tracking(1)
                }
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "music.note").font(.title3).foregroundStyle(CoroStyle.accent)
                            .frame(width: 44, height: 44).background(CoroStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.track?.title ?? "Tu próxima canción")
                                .font(.headline).lineLimit(2)
                            Text(session.track?.artists.joined(separator: ", ") ?? "La música sigue en Spotify")
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                    Text(session.line)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(session.running ? CoroStyle.accent : .white)
                        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
                        .accessibilityLabel("Línea actual: \(session.line)")
                    if !session.nextLine.isEmpty {
                        Text(session.nextLine).font(.title3).foregroundStyle(.secondary)
                            .accessibilityLabel("Siguiente línea: \(session.nextLine)")
                    }
                    if !session.notice.isEmpty {
                        Text(session.notice).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CoroStyle.card, in: RoundedRectangle(cornerRadius: 28))

                VStack(spacing: 12) {
                    if session.running {
                        Button { blackScreen.enable() } label: {
                            Label("Pantalla negra", systemImage: "moon.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).foregroundStyle(.black)
                        Text("Deja Coro abierto y el iPhone desbloqueado. No pulses el botón lateral. Toca dos veces la pantalla negra para volver; se restaurará el brillo anterior.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { session.stop() } label: {
                            Label("Detener sesión", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                    } else if auth.isConnected {
                        Button { Task { await session.start() } } label: {
                            Label(session.starting ? "Preparando…" : "Iniciar letras", systemImage: "play.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).foregroundStyle(.black)
                        .disabled(session.starting)
                    } else {
                        Button {
                            if auth.clientID.isEmpty { settings = true }
                            else { Task { await auth.connect() } }
                        } label: {
                            Label(auth.isAuthorizing ? "Conectando…" : "Conectar Spotify", systemImage: "link")
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).foregroundStyle(.black)
                        .disabled(auth.isAuthorizing)
                    }
                    if !session.running {
                        Button("Ver demostración de 45 segundos") { Task { await session.start(demo: true) } }
                            .font(.subheadline).padding(.vertical, 8)
                            .disabled(session.starting || auth.isAuthorizing)
                    }
                    Link(destination: session.track?.spotifyURL ?? URL(string: "https://open.spotify.com/")!) {
                        Label("Reproducción en Spotify", systemImage: "arrow.up.right")
                            .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    }
                }

                if let message = session.message ?? auth.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("En CarPlay", systemImage: "car.side").font(.subheadline.weight(.semibold))
                    Text("Inicia la sesión, abre el panel de CarPlay y activa Pantalla negra en Coro. La letra permanece junto a las otras apps del panel. Mantén Coro abierto: bloquear el iPhone o cambiar de app puede congelar las letras.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Letras: LRCLIB · La disponibilidad depende de cada canción.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
            .padding(24)
        }
        .background(CoroStyle.background)
    }
}

import SwiftUI

struct SettingsView: View {
    @ObservedObject var session: SessionController
    @ObservedObject var auth: SpotifyAuth
    @Environment(\.dismiss) private var dismiss
    @State private var clientID = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Client ID de Spotify", text: $clientID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                        .disabled(session.running)
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                    Button("Guardar Client ID") {
                        do { try auth.configure(clientID: clientID); error = nil; dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                    .disabled(session.running || clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("Solo se necesita el identificador público de tu app personal. Nunca pegues tu contraseña ni el Client Secret.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Spotify") }

                Section("Desfase de la letra") {
                    Stepper(value: $session.offset, in: -10...10, step: 0.25) {
                        Text(String(format: "%+.2f segundos", session.offset)).monospacedDigit()
                    }
                    Text("Positivo: la letra aparece antes. Negativo: después. Ajusta con una canción que conozcas.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Restablecer a cero") { session.offset = 0 }
                }

                Section("Pantalla negra") {
                    Text("Inicia las letras y pulsa Pantalla negra en la pantalla principal. Coro bajará el brillo y evitará el bloqueo automático mientras este modo esté activo. El iPhone sigue desbloqueado.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Toca dos veces para volver. Al salir del modo, cambiar de app o terminar la sesión se restauran el brillo y el bloqueo automático anteriores.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Segundo plano experimental") {
                    Toggle("Mantener la sesión activa", isOn: $session.keepAlive).disabled(session.running)
                    Text("Reproduce silencio local mezclado con Spotify para intentar mantener Coro activo fuera de la app. No garantiza que las letras avancen con el iPhone bloqueado. Pantalla negra no necesita esta opción. Cámbiala con la sesión detenida.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("La sesión termina al desconectar CarPlay o tras dos minutos sin reproducción.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Preparación inicial") {
                    Link("Abrir Spotify for Developers", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                    Text("Redirect URI exacta:").font(.footnote)
                    Text(LoopbackCallback.redirect).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text("En la app de Spotify for Developers selecciona Web API y guarda esta dirección. Después copia aquí el Client ID. Usa la misma cuenta Premium.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Tus datos") {
                    Text("El acceso de Spotify se guarda en el llavero de este iPhone. Solo consultamos la reproducción. Para buscar letras se envían a LRCLIB título, artista, álbum y duración. No hay cuenta de Coro, anuncios ni analítica.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if auth.isConnected {
                        Button("Desconectar Spotify y borrar acceso", role: .destructive) { session.disconnect() }
                    }
                    Link("Administrar permisos en Spotify", destination: URL(string: "https://www.spotify.com/account/apps/")!)
                    Link("Fuente de letras: LRCLIB", destination: URL(string: "https://lrclib.net/")!)
                }
                Section {
                    Text("Coro 0.1.2 · Prototipo para uso personal. No está afiliado a Spotify ni a Apple.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .onAppear { clientID = auth.clientID }
        }
        .preferredColorScheme(.dark).tint(CoroStyle.accent)
    }
}

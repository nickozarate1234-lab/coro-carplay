import Foundation
import Combine
import CryptoKit
import Security

struct AuthorizationPage: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class SpotifyAuth: ObservableObject {
    @Published private(set) var clientID: String
    @Published private(set) var isConnected = false
    @Published private(set) var isAuthorizing = false
    @Published var page: AuthorizationPage?
    @Published var message: String?
    private var credentials: SpotifyCredentials?
    private var pending: (verifier: String, state: String)?
    private let callbackServer = LoopbackCallback()
    private var timeout: Task<Void, Never>?
    private var refresh: Task<String, Error>?
    private var generation = 0

    init() {
        clientID = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""
        credentials = KeychainStore.load()
        isConnected = credentials != nil && !clientID.isEmpty
    }

    func configure(clientID: String) throws {
        let value = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil else {
            throw CoroError.message("El Client ID debe tener 32 caracteres. No pegues el Client Secret ni tu contraseña.")
        }
        if value != self.clientID { disconnect() }
        self.clientID = value
        UserDefaults.standard.set(value, forKey: "spotifyClientID")
    }

    func connect() async {
        guard !isAuthorizing else { return }
        guard !clientID.isEmpty else { message = "Primero añade el Client ID en Ajustes."; return }
        isAuthorizing = true
        generation += 1
        message = nil
        do {
            let verifier = try Self.randomString()
            let state = try Self.randomString()
            pending = (verifier, state)
            try await callbackServer.start { [weak self] url in
                Task { @MainActor in await self?.finish(url) }
            }
            let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
            var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
            url.queryItems = [
                .init(name: "client_id", value: clientID),
                .init(name: "response_type", value: "code"),
                .init(name: "redirect_uri", value: LoopbackCallback.redirect),
                .init(name: "scope", value: "user-read-currently-playing"),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "code_challenge", value: challenge),
                .init(name: "state", value: state)
            ]
            page = AuthorizationPage(url: url.url!)
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
                guard let self, self.pending != nil else { return }
                self.cancelLogin()
                self.message = "La conexión tardó demasiado. Inténtalo otra vez."
            }
        } catch {
            cancelLogin()
            message = "No se pudo iniciar la conexión: \(error.localizedDescription)"
        }
    }

    private func finish(_ url: URL) async {
        guard let flow = pending else { return }
        let operation = generation
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == flow.state else {
            message = "Se rechazó una respuesta de acceso no válida."
            return
        }
        timeout?.cancel()
        pending = nil
        page = nil
        callbackServer.stop()
        defer { if generation == operation { isAuthorizing = false } }
        if items.contains(where: { $0.name == "error" }) {
            message = "Spotify no autorizó el acceso. Puedes intentarlo de nuevo."
            return
        }
        guard items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            message = "Spotify devolvió una respuesta incompleta."
            return
        }
        do {
            let response = try await tokenRequest([
                "client_id": clientID, "grant_type": "authorization_code", "code": code,
                "redirect_uri": LoopbackCallback.redirect, "code_verifier": flow.verifier
            ])
            guard generation == operation else { return }
            guard let refreshToken = response.refresh_token, !refreshToken.isEmpty else { throw CoroError.unauthorized }
            try store(response, refreshToken: refreshToken)
            message = "Spotify conectado."
        } catch { if generation == operation { message = error.localizedDescription } }
    }

    func dismissAuthorization() {
        if pending != nil { cancelLogin() }
    }

    func cancelLogin() {
        timeout?.cancel()
        timeout = nil
        callbackServer.stop()
        pending = nil
        page = nil
        isAuthorizing = false
    }

    func disconnect() {
        generation += 1
        cancelLogin()
        refresh?.cancel()
        refresh = nil
        KeychainStore.clear()
        credentials = nil
        isConnected = false
        message = nil
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let existing = credentials else { throw CoroError.unauthorized }
        if !forceRefresh, existing.expiresAt.timeIntervalSinceNow > 60 { return existing.accessToken }
        if let refresh { return try await refresh.value }
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw CoroError.unauthorized }
            let result = try await self.tokenRequest([
                "client_id": self.clientID, "grant_type": "refresh_token", "refresh_token": existing.refreshToken
            ])
            try Task.checkCancellation()
            try self.store(result, refreshToken: result.refresh_token ?? existing.refreshToken)
            return result.access_token
        }
        refresh = task
        defer { refresh = nil }
        return try await task.value
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Network.form(fields)
        let (data, response) = try await Network.request(request)
        guard response.statusCode == 200 else {
            if response.statusCode == 400 || response.statusCode == 401 { throw CoroError.unauthorized }
            throw CoroError.message("Spotify no pudo completar el acceso (\(response.statusCode)).")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func store(_ response: TokenResponse, refreshToken: String) throws {
        let value = SpotifyCredentials(accessToken: response.access_token, refreshToken: refreshToken,
                                       expiresAt: Date().addingTimeInterval(response.expires_in))
        try KeychainStore.save(value)
        credentials = value
        isConnected = true
    }

    private static func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CoroError.message("No se pudo preparar una conexión segura.")
        }
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

import Foundation
import LyricsCore

enum CoroError: LocalizedError {
    case message(String)
    case rateLimited(TimeInterval)
    case unauthorized
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .rateLimited: return "El servicio pide una pausa. Coro reintentará automáticamente."
        case .unauthorized: return "Vuelve a conectar Spotify."
        }
    }
}

enum Network {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func request(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CoroError.message("Respuesta de red no válida.") }
        if http.statusCode == 429 || http.statusCode == 503 {
            throw CoroError.rateLimited(RetryDelay.seconds(from: http.value(forHTTPHeaderField: "Retry-After")))
        }
        return (data, http)
    }

    static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
}

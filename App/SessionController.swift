import Foundation
import Combine
import AVFoundation
import LyricsCore

@MainActor
final class SessionController: ObservableObject {
    let auth: SpotifyAuth
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var isDemo = false
    @Published private(set) var isPlaying = false
    @Published private(set) var track: Track?
    @Published private(set) var line = "Tu música. Tu momento."
    @Published private(set) var nextLine = ""
    @Published private(set) var notice = "Conecta Spotify para empezar."
    @Published private(set) var lastConfirmed: Date?
    @Published var message: String?
    @Published var offset: Double {
        didSet {
            if offset.isFinite { UserDefaults.standard.set(offset, forKey: "lyricsOffset") }
        }
    }
    @Published var keepAlive: Bool {
        didSet { UserDefaults.standard.set(keepAlive, forKey: "keepAlive") }
    }
    private let spotify: SpotifyClient
    private let lyricsClient = LyricsClient()
    private let live = LiveActivityController()
    private let background = BackgroundAudio()
    private var snapshot: SpotifySnapshot?
    private var lines: [LyricLine] = []
    private var lyricsNotice = ""
    private var pollTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var idleSince: TimeInterval?
    private var startedAt = Date()
    private var observers: [NSObjectProtocol] = []

    init(auth: SpotifyAuth) {
        self.auth = auth
        self.spotify = SpotifyClient(auth: auth)
        let stored = UserDefaults.standard.double(forKey: "lyricsOffset")
        offset = stored.isFinite ? min(10, max(-10, stored)) : 0
        keepAlive = UserDefaults.standard.object(forKey: "keepAlive") as? Bool ?? true
        live.onDismiss = { [weak self] in
            guard let self, self.running else { return }
            self.stop(reason: "Actividad en vivo cerrada. Sesión terminada.")
        }
        observeSystem()
    }

    func start(demo: Bool = false) async {
        guard !running, !starting else { return }
        guard demo || auth.isConnected else { message = "Conecta Spotify antes de iniciar."; return }
        starting = true
        defer { starting = false }
        message = nil
        do {
            if keepAlive { try background.start() }
            try await live.start(demo: demo)
        } catch {
            background.stop()
            message = error.localizedDescription
            return
        }
        running = true
        isDemo = demo
        snapshot = nil
        track = nil
        lines = []
        lastConfirmed = nil
        idleSince = nil
        startedAt = Date()
        line = "Preparando letras…"
        nextLine = ""
        notice = demo ? "DEMO · Sin conexión a Spotify" : "Esperando a Spotify…"
        if demo {
            lines = LRCParser.parse(Self.demoLyrics)
            let song = Track(id: "coro-demo", title: "Demostración", artists: ["Texto de prueba de Coro"],
                             album: "", duration: 45, spotifyURL: nil)
            let anchor = PlaybackAnchor(position: 0, duration: 45, observedAt: ProcessInfo.processInfo.systemUptime, isPlaying: true)
            snapshot = SpotifySnapshot(track: song, anchor: anchor, confirmedAt: Date())
            track = song
        } else {
            pollTask = Task { [weak self] in await self?.poll() }
        }
        renderTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.running else { return }
                let delay = await self.render()
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            }
        }
    }

    func stop(reason: String? = nil) {
        running = false
        isPlaying = false
        pollTask?.cancel(); pollTask = nil
        renderTask?.cancel(); renderTask = nil
        lyricsTask?.cancel(); lyricsTask = nil
        background.stop()
        live.stop()
        snapshot = nil
        track = nil
        lines = []
        lastConfirmed = nil
        line = "Tu música. Tu momento."
        nextLine = ""
        notice = "Sesión detenida"
        if let reason { message = reason }
    }

    func disconnect() {
        stop()
        auth.disconnect()
        Task { await lyricsClient.clear() }
        notice = "Spotify desconectado."
    }

    private func poll() async {
        var failures = 0
        while !Task.isCancelled, running {
            var delay: Double = 5
            do {
                let latest = try await spotify.current()
                try Task.checkCancellation()
                guard running else { return }
                failures = 0
                message = nil
                snapshot = latest
                lastConfirmed = latest?.confirmedAt
                if latest?.track.id != track?.id {
                    lyricsTask?.cancel()
                    track = latest?.track
                    lines = []
                    lyricsNotice = "Buscando letra…"
                    if let song = latest?.track { loadLyrics(song) }
                }
                let now = ProcessInfo.processInfo.systemUptime
                if latest?.anchor.isPlaying == true { idleSince = nil }
                else if idleSince == nil { idleSince = now }
                if let idleSince, now - idleSince >= 120 {
                    stop(reason: "Sesión terminada tras dos minutos sin reproducir. Inicia Coro cuando vuelvas a escuchar música.")
                    return
                }
                if latest == nil || latest?.anchor.isPlaying == false { delay = 8 }
            } catch is CancellationError { return }
            catch CoroError.rateLimited(let seconds) {
                delay = seconds + Double.random(in: 0...min(5, max(0.1, seconds * 0.2)))
                message = "Spotify pide esperar. Coro respetará la pausa y reintentará solo."
            } catch CoroError.unauthorized {
                stop(reason: "El acceso de Spotify venció o fue revocado. Desconecta y vuelve a conectarlo en Ajustes.")
                return
            } catch {
                failures += 1
                delay = min(60, pow(2, Double(min(failures, 5))) * 2)
                message = error.localizedDescription
            }
            do { try await Self.sleep(seconds: delay) } catch { return }
        }
    }

    private func loadLyrics(_ song: Track) {
        lyricsTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let result = try await self.lyricsClient.get(for: song)
                    try Task.checkCancellation()
                    guard self.running, self.track?.id == song.id else { return }
                    self.lines = result.lines
                    self.lyricsNotice = result.notice
                    return
                } catch is CancellationError { return }
                catch CoroError.rateLimited(let delay) {
                    self.lyricsNotice = "La fuente de letras pide esperar…"
                    do { try await Self.sleep(seconds: delay) } catch { return }
                } catch {
                    guard self.track?.id == song.id, !Task.isCancelled else { return }
                    self.lyricsNotice = "No se pudo obtener la letra. Reintentando…"
                    do { try await Self.sleep(seconds: 30) } catch { return }
                }
            }
        }
    }

    private func render() async -> Double {
        guard running else { return 1 }
        if !isDemo, Date().timeIntervalSince(lastConfirmed ?? startedAt) >= 300 {
            stop(reason: "Cinco minutos sin confirmar reproducción en Spotify. Sesión detenida para evitar consumo innecesario.")
            return 1
        }
        if Date().timeIntervalSince(startedAt) >= 7 * 3600 {
            stop(reason: "Sesión completada. Puedes iniciar otra cuando quieras.")
            return 1
        }
        let now = ProcessInfo.processInfo.systemUptime
        var confirmedAt = lastConfirmed
        var visibleLine = "Reproduce una canción en Spotify"
        var followingLine = ""
        var visibleNotice = "Esperando música"
        var playing = false
        var delay: Double = 1
        if let snapshot {
            if isDemo {
                confirmedAt = Date()
                if snapshot.anchor.position(at: now) >= 45 { stop(reason: "Demostración terminada."); return 1 }
            }
            playing = snapshot.anchor.isPlaying
            if !isDemo, !snapshot.anchor.isFresh(at: now) {
                playing = false
                visibleLine = "Esperando a Spotify…"
                visibleNotice = "Sin confirmación reciente. No mostramos una letra desfasada."
            } else if lines.isEmpty {
                visibleLine = lyricsNotice.isEmpty ? "Sin letra sincronizada" : lyricsNotice
                visibleNotice = playing ? "" : "En pausa"
            } else {
                let position = snapshot.anchor.position(at: now) + offset
                if let index = LRCParser.index(at: position, in: lines) {
                    visibleLine = lines[index].text.isEmpty ? "♪" : lines[index].text
                    followingLine = index + 1 < lines.count ? lines[index + 1].text : ""
                    if playing, index + 1 < lines.count { delay = min(1, max(0.05, lines[index + 1].time - position)) }
                } else {
                    visibleLine = "♪"
                    followingLine = lines.first?.text ?? ""
                    if playing, let first = lines.first { delay = min(1, max(0.05, first.time - position)) }
                }
                visibleNotice = isDemo ? "DEMO · Texto de prueba" : (playing ? "" : "En pausa")
            }
        }
        if line != visibleLine { line = visibleLine }
        if nextLine != followingLine { nextLine = followingLine }
        if notice != visibleNotice { notice = visibleNotice }
        if isPlaying != playing { isPlaying = playing }
        let state = CoroAttributes.ContentState(title: String((track?.title ?? "Coro").prefix(100)),
                                                artist: String((track?.artists.joined(separator: ", ") ?? "").prefix(120)),
                                                line: String(line.prefix(240)), nextLine: String(nextLine.prefix(240)),
                                                notice: String(notice.prefix(120)), isPlaying: isPlaying, isDemo: isDemo)
        await live.update(state, confirmedAt: confirmedAt)
        return delay
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in
                guard let self, self.running else { return }
                self.stop(reason: "El sistema interrumpió la sesión de audio. Vuelve a iniciar Coro cuando termine la llamada o Siri.")
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let previous = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
                  previous.outputs.contains(where: { $0.portType == .carAudio }) else { return }
            Task { @MainActor in
                guard let self, self.running,
                      !AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .carAudio }) else { return }
                self.stop(reason: "CarPlay desconectado. Sesión terminada.")
            }
        })
    }

    private static func sleep(seconds: Double) async throws {
        // Chunk very long server cooldowns without ever retrying before Retry-After.
        let deadline = ProcessInfo.processInfo.systemUptime + max(1, seconds)
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            let remaining = min(60, max(0.01, deadline - ProcessInfo.processInfo.systemUptime))
            try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
    }

    private static let demoLyrics = """
    [00:00]Así se verá tu letra
    [00:05]Esta línea es una demostración
    [00:10]El texto sigue el tiempo
    [00:15]Y aquí aparece la siguiente línea
    [00:20]
    [00:25]Puedes corregir el desfase en Ajustes
    [00:32]Después conecta tu cuenta de Spotify
    [00:39]Demostración completada
    """
}

import Foundation
import ActivityKit

@MainActor
final class LiveActivityController {
    private var activity: Activity<CoroAttributes>?
    private var previous: CoroAttributes.ContentState?
    private var lastUpdate = Date.distantPast
    private var stateTask: Task<Void, Never>?
    var onDismiss: (() -> Void)?

    func start(demo: Bool) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw CoroError.message("Activa las Actividades en vivo de Coro en Ajustes del iPhone.")
        }
        // Clean up activities left by a force quit or a previous installation.
        for old in Activity<CoroAttributes>.activities {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        let initial = CoroAttributes.ContentState(title: demo ? "Demostración" : "Coro", artist: "",
                                                  line: "Preparando letras…", nextLine: "", notice: "",
                                                  isPlaying: false, isDemo: demo)
        activity = try Activity.request(attributes: CoroAttributes(sessionID: UUID()),
                                        content: ActivityContent(state: initial, staleDate: Date().addingTimeInterval(20)),
                                        pushType: nil)
        stateTask?.cancel()
        if let activity {
            stateTask = Task { [weak self] in
                for await state in activity.activityStateUpdates {
                    guard !Task.isCancelled, let self, self.activity?.id == activity.id else { return }
                    if state == .dismissed || state == .ended {
                        self.onDismiss?()
                        return
                    }
                }
            }
        }
        previous = initial
        lastUpdate = Date()
    }

    func update(_ state: CoroAttributes.ContentState, confirmedAt: Date?) async {
        guard let activity else { return }
        let fitted = Self.fit(state)
        guard fitted != previous || Date().timeIntervalSince(lastUpdate) >= 10 else { return }
        // The stale date always reflects real Spotify confirmation, not our local timer.
        let expires = (confirmedAt ?? Date()).addingTimeInterval(20)
        await activity.update(ActivityContent(state: fitted, staleDate: expires))
        previous = fitted
        lastUpdate = Date()
    }

    private static func fit(_ state: CoroAttributes.ContentState) -> CoroAttributes.ContentState {
        var value = state
        // ActivityKit permits 4 KB total; leave room for attributes and wrappers.
        // Measure encoded bytes because Unicode graphemes and JSON escaping vary.
        while ((try? JSONEncoder().encode(value).count) ?? Int.max) > 3400 {
            if !value.nextLine.isEmpty { value.nextLine = "" }
            else if !value.artist.isEmpty { value.artist = "" }
            else if !value.notice.isEmpty { value.notice = "" }
            else if value.title != "Coro" { value.title = "Coro" }
            else if !value.line.isEmpty { value.line = String(value.line.prefix(value.line.count / 2)) }
            else { break }
        }
        return value
    }

    func stop() {
        let old = activity
        activity = nil
        stateTask?.cancel()
        stateTask = nil
        previous = nil
        if let old { Task { await old.end(nil, dismissalPolicy: .immediate) } }
    }
}

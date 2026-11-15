import Combine
import UIKit

/// Keeps the phone app visible behind a black surface. This does not lock iOS.
@MainActor
final class BlackScreenController: ObservableObject {
    @Published private(set) var isEnabled = false
    private var screen: UIScreen?
    private var previousBrightness: CGFloat = 0
    private var previousIdleTimerDisabled = false

    func enable() {
        guard !isEnabled, UIApplication.shared.applicationState == .active,
              let phoneScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.session.role == .windowApplication && $0.activationState == .foregroundActive })
        else { return }

        screen = phoneScene.screen
        previousBrightness = phoneScene.screen.brightness
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        phoneScene.screen.brightness = 0
        isEnabled = true
    }

    func disable() {
        guard isEnabled else { return }
        screen?.brightness = previousBrightness
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        screen = nil
        isEnabled = false
    }
}

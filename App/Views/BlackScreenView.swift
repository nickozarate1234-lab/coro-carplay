import SwiftUI

struct BlackScreenView: View {
    let onExit: () -> Void

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onExit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Salir de la pantalla negra y volver a Coro")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(onExit)
    }
}

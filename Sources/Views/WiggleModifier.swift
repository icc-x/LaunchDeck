import SwiftUI

struct WiggleModifier: ViewModifier {
    let isActive: Bool
    let seed: String

    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive ? (isAnimating ? 0.85 : -0.85) : 0))
            .offset(y: isActive ? (isAnimating ? 0.35 : -0.35) : 0)
            .onAppear {
                updateAnimationState()
            }
            .onChange(of: isActive) { _, _ in
                updateAnimationState()
            }
    }

    private func updateAnimationState() {
        if isActive {
            guard !isAnimating else { return }
            withAnimation(
                .easeInOut(duration: 0.15)
                    .repeatForever(autoreverses: true)
                    .delay(animationDelay(for: seed))
            ) {
                isAnimating = true
            }
        } else {
            isAnimating = false
        }
    }

    private func animationDelay(for value: String) -> Double {
        let hashed = abs(value.hashValue % 127)
        return Double(hashed) / 127.0 * 0.09
    }
}

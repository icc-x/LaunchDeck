import SwiftUI

enum LaunchMotion {
    static let reorder = Animation.interactiveSpring(
        response: 0.28,
        dampingFraction: 0.84,
        blendDuration: 0.16
    )

    static let page = Animation.interactiveSpring(
        response: 0.46,
        dampingFraction: 0.90,
        blendDuration: 0.22
    )

    static let modal = Animation.interactiveSpring(
        response: 0.42,
        dampingFraction: 0.88,
        blendDuration: 0.18
    )

    static let hover = Animation.spring(
        response: 0.30,
        dampingFraction: 0.86,
        blendDuration: 0.12
    )

    static let smooth = Animation.easeInOut(duration: 0.28)
    static let quickFade = Animation.easeInOut(duration: 0.20)
}

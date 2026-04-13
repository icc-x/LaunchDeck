import SwiftUI

struct LaunchTheme {
    let colorScheme: ColorScheme

    var isDark: Bool {
        colorScheme == .dark
    }

    var textPrimary: Color {
        isDark ? .white.opacity(0.92) : Color(red: 0.16, green: 0.17, blue: 0.19)
    }

    var textSecondary: Color {
        isDark ? .white.opacity(0.74) : Color(red: 0.30, green: 0.31, blue: 0.35)
    }

    var textTertiary: Color {
        isDark ? .white.opacity(0.64) : Color.black.opacity(0.54)
    }

    var controlForeground: Color {
        isDark ? .white.opacity(0.92) : Color(red: 0.16, green: 0.17, blue: 0.20)
    }

    var controlSubtleForeground: Color {
        isDark ? .white.opacity(0.80) : Color(red: 0.24, green: 0.25, blue: 0.28)
    }

    var controlStroke: Color {
        isDark ? .white.opacity(0.24) : .black.opacity(0.18)
    }

    var cardStroke: Color {
        isDark ? .white.opacity(0.24) : .black.opacity(0.14)
    }

    var dropStroke: Color {
        isDark ? .white.opacity(0.72) : .black.opacity(0.56)
    }

    var pageIndicatorActive: Color {
        isDark ? .white : .black.opacity(0.84)
    }

    var pageIndicatorInactive: Color {
        isDark ? .white.opacity(0.35) : .black.opacity(0.30)
    }

    var modalMask: Color {
        isDark ? .black.opacity(0.28) : .black.opacity(0.16)
    }

    var dragHintStroke: Color {
        isDark ? .white.opacity(0.25) : .black.opacity(0.22)
    }

    var tileShadowHover: Color {
        .black.opacity(isDark ? 0.22 : 0.15)
    }

    var tileShadowNormal: Color {
        .black.opacity(isDark ? 0.12 : 0.08)
    }

    var searchFieldStroke: Color {
        isDark ? .white.opacity(0.24) : .black.opacity(0.16)
    }

    var backdropTint: [Color] {
        if isDark {
            return [
                Color.black.opacity(0.12),
                Color.black.opacity(0.07),
                Color.black.opacity(0.10)
            ]
        }
        return [
            Color.white.opacity(0.08),
            Color.white.opacity(0.04),
            Color.black.opacity(0.06)
        ]
    }
}

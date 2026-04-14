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

    var controlFill: Color {
        if isDark {
            return Color.white.opacity(0.10)
        }
        return Color.white.opacity(0.78)
    }

    var controlFillStrong: Color {
        if isDark {
            return Color.white.opacity(0.14)
        }
        return Color.white.opacity(0.88)
    }

    var cardStroke: Color {
        isDark ? .white.opacity(0.24) : .black.opacity(0.14)
    }

    var panelFill: Color {
        if isDark {
            return Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.94)
        }
        return Color(red: 0.96, green: 0.97, blue: 0.99).opacity(0.92)
    }

    var folderCardFill: Color {
        if isDark {
            return Color.white.opacity(0.08)
        }
        return Color.white.opacity(0.76)
    }

    var dropStroke: Color {
        isDark ? .white.opacity(0.72) : .black.opacity(0.56)
    }

    var placeholderFill: Color {
        isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.56)
    }

    var placeholderStroke: Color {
        isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.12)
    }

    var placeholderSecondaryFill: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    var dragPreviewFill: Color {
        if isDark {
            return Color(red: 0.12, green: 0.13, blue: 0.17).opacity(0.92)
        }
        return Color.white.opacity(0.96)
    }

    var dragPreviewStroke: Color {
        isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10)
    }

    var dragPreviewShadow: Color {
        .black.opacity(isDark ? 0.34 : 0.22)
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

    var backdropBase: [Color] {
        if isDark {
            return [
                Color(red: 0.07, green: 0.08, blue: 0.10),
                Color(red: 0.10, green: 0.11, blue: 0.14),
                Color(red: 0.08, green: 0.09, blue: 0.12)
            ]
        }
        return [
            Color(red: 0.97, green: 0.98, blue: 0.995),
            Color(red: 0.93, green: 0.95, blue: 0.98),
            Color(red: 0.90, green: 0.93, blue: 0.97)
        ]
    }

    var backdropGlow: [Color] {
        if isDark {
            return [
                Color.white.opacity(0.07),
                Color.clear
            ]
        }
        return [
            Color.white.opacity(0.24),
            Color.clear
        ]
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

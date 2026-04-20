import SwiftUI

struct LauncherFooterBar: View {
    let statusMessage: String
    let pagesCount: Int
    let currentPage: Int
    let showDetails: Bool
    let detailText: String?
    let pageIndicatorActive: Color
    let pageIndicatorInactive: Color
    let textSecondary: Color
    let onGoToPage: (Int) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(statusMessage)
                .font(.callout)
                .foregroundStyle(textSecondary)
                .lineLimit(1)

            if showDetails, let detailText {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(textSecondary.opacity(0.85))
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }

            if pagesCount > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<pagesCount, id: \.self) { index in
                        Button {
                            onGoToPage(index)
                        } label: {
                            Circle()
                                .fill(index == currentPage ? pageIndicatorActive : pageIndicatorInactive)
                                .frame(width: 8, height: 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LaunchDeckStrings.pagePosition(current: index + 1, total: pagesCount))
                    }
                }
            }
        }
    }
}

#Preview("Footer — 3 pages") {
    LauncherFooterBar(
        statusMessage: "42 apps",
        pagesCount: 3,
        currentPage: 1,
        showDetails: true,
        detailText: "Page 2 of 3",
        pageIndicatorActive: .accentColor,
        pageIndicatorInactive: .secondary.opacity(0.4),
        textSecondary: .secondary,
        onGoToPage: { _ in }
    )
    .padding()
    .frame(width: 480)
    .background(LaunchpadBackdrop())
}

#Preview("Footer — single page") {
    LauncherFooterBar(
        statusMessage: "Scanning…",
        pagesCount: 1,
        currentPage: 0,
        showDetails: false,
        detailText: nil,
        pageIndicatorActive: .accentColor,
        pageIndicatorInactive: .secondary.opacity(0.4),
        textSecondary: .secondary,
        onGoToPage: { _ in }
    )
    .padding()
    .frame(width: 480)
    .background(LaunchpadBackdrop())
}

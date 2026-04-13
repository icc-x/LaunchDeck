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

import SwiftUI

extension View {
    @ViewBuilder
    func conditionalModifier<Modified: View>(
        _ condition: Bool,
        transform: (Self) -> Modified
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

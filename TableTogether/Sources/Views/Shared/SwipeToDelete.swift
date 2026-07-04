import SwiftUI

/// Swipe-left-to-reveal a Delete button, for rows that live in a `LazyVStack`
/// rather than a `List` (where `.swipeActions` would be available). Used by the
/// meal log and the week planner so both surfaces delete the same way. A tap
/// elsewhere while revealed closes it without deleting.
struct SwipeToDelete: ViewModifier {
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    private let revealWidth: CGFloat = 88

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(AppTypography.caption)
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(offset < 0 ? 1 : 0)

            content
                .background(Theme.Colors.background)
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            if value.translation.width < 0
                                && abs(value.translation.width) > abs(value.translation.height) {
                                offset = max(value.translation.width, -revealWidth)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = value.translation.width < -revealWidth / 2 ? -revealWidth : 0
                            }
                        }
                )
        }
    }
}

extension View {
    /// Adds swipe-left-to-delete to a row in a non-`List` container.
    func swipeToDelete(perform onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(onDelete: onDelete))
    }
}

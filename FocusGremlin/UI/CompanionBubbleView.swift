import SwiftUI

struct CompanionBubbleView: View {
    @ObservedObject var viewModel: CompanionViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                GremlinAvatar()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Focus Gremlin")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if viewModel.phase == .typingDots {
                        TypingDotsView()
                            .frame(height: 18)
                    } else if !viewModel.visibleText.isEmpty {
                        Text(viewModel.visibleText)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35), lineWidth: 1)
        )
        .opacity(viewModel.bubbleOpacity)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: viewModel.visibleText)
        .padding(8)
    }
}

private struct GremlinAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.85), Color.blue.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("😈")
                .font(.system(size: 22))
        }
        .frame(width: 38, height: 38)
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        )
    }
}

import SwiftUI

struct CompanionBubbleView: View {
    @ObservedObject var viewModel: CompanionViewModel
    @Environment(\.colorScheme) private var colorScheme

    /// Ширина под длинные фразы; `NSHostingView.fittingSize` подстроит панель по высоте.
    private var bubbleMaxWidth: CGFloat { 520 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                GremlinAvatar(viewModel: viewModel)
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
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
        }
        .padding(14)
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
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
    @ObservedObject var viewModel: CompanionViewModel

    private let avatarSize: CGFloat = 38

    /// Точки ожидания и набор текста — лист «на курсор/на строку»; удержание — idle.
    private var useTypingSprite: Bool {
        viewModel.phase == .typingDots || viewModel.phase == .streaming
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.55),
                            Color.blue.opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            // Тёмная подложка, чтобы чёрный фон спрайт-листа не резал глаз у кромки круга.
            Circle()
                .fill(Color(white: 0.12))
                .padding(2)
            let inner = avatarSize - 4
            if viewModel.phase == .dismissing, let t0 = viewModel.dismissSpriteStartedAt {
                GremlinDismissSpriteView(size: inner, startDate: t0)
            } else {
                ZStack {
                    GremlinIdleSpriteView(size: inner)
                        .opacity(useTypingSprite ? 0 : 1)
                    GremlinTypingSpriteView(size: inner)
                        .id(viewModel.typingSpriteEpoch)
                        .opacity(useTypingSprite ? 1 : 0)
                }
                .animation(.easeInOut(duration: 0.13), value: useTypingSprite)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        )
    }
}

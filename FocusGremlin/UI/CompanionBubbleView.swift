import SwiftUI

struct CompanionBubbleView: View {
    @ObservedObject var viewModel: CompanionViewModel

    private var textMaxWidth: CGFloat { 540 }
    /// Яркий зелёный для строки под гремлином.
    private static let lineGreen = Color(red: 0.12, green: 0.82, blue: 0.32)

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            GremlinSpriteCharacterView(viewModel: viewModel)

            Group {
                if viewModel.phase == .typingDots {
                    TypingDotsView()
                } else if !viewModel.visibleText.isEmpty {
                    Text(viewModel.visibleText)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Self.lineGreen)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 1)
                }
            }
            .frame(maxWidth: textMaxWidth, minHeight: 0, alignment: .center)
        }
        .frame(width: textMaxWidth + 32, alignment: .top)
        .background(Color.clear)
        .compositingGroup()
        .opacity(viewModel.bubbleOpacity)
    }
}

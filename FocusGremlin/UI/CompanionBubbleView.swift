import SwiftUI

struct CompanionBubbleView: View {
    @ObservedObject var viewModel: CompanionViewModel

    private var gremlinHeight: CGFloat { GremlinOverlaySpriteMetrics.displayHeight }
    private var textMaxWidth: CGFloat { 540 }
    /// Яркий зелёный для строки под гремлином.
    private static let lineGreen = Color(red: 0.12, green: 0.82, blue: 0.32)

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            FloatingGremlinAnimation(viewModel: viewModel, displayHeight: gremlinHeight)

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
            .frame(maxWidth: textMaxWidth, alignment: .center)
        }
        .frame(maxWidth: textMaxWidth + 32)
        .background(Color.clear)
        .opacity(viewModel.bubbleOpacity)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: viewModel.visibleText)
    }
}

/// Только спрайты. Idle и «говорение» **не** кладём в один ZStack с opacity — иначе при анимации видны два кадра сразу («туалетная бумага»).
private struct FloatingGremlinAnimation: View {
    @ObservedObject var viewModel: CompanionViewModel
    var displayHeight: CGFloat

    private var useTypingSprite: Bool {
        viewModel.phase == .typingDots || viewModel.phase == .streaming
    }

    @ViewBuilder
    private var typingSprite: some View {
        Group {
            if viewModel.deliverySpeechStyle == .negation {
                GremlinTalkingNegateSpriteView(displayHeight: displayHeight)
            } else {
                switch viewModel.cursorZone {
                case .center:
                    GremlinTalkingCenterSpriteView(displayHeight: displayHeight)
                case .right:
                    GremlinTalkingRightSpriteView(displayHeight: displayHeight)
                case .left:
                    GremlinTypingSpriteView(displayHeight: displayHeight)
                }
            }
        }
        .id(viewModel.typingSpriteEpoch)
    }

    var body: some View {
        Group {
            if viewModel.phase == .dismissing, let t0 = viewModel.dismissSpriteStartedAt {
                GremlinDismissSpriteView(displayHeight: displayHeight, startDate: t0)
            } else if useTypingSprite {
                typingSprite
            } else {
                GremlinIdleSpriteView(displayHeight: displayHeight)
            }
        }
        .frame(height: displayHeight)
        .fixedSize(horizontal: true, vertical: false)
        .animation(nil, value: viewModel.cursorZone)
        .animation(nil, value: viewModel.deliverySpeechStyle)
    }
}

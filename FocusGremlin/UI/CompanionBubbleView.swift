import SwiftUI

struct CompanionBubbleView: View {
    @ObservedObject var viewModel: CompanionViewModel

    private var textMaxWidth: CGFloat { 540 }
    /// Яркий зелёный для строки под гремлином.
    private static let lineGreen = Color(red: 0.12, green: 0.82, blue: 0.32)
    /// Вставка/снятие без отдельного transition — появление ведёт `companionPresentOpacity` / scale во `CompanionViewModel`.
    private static let spriteMountTransition = AnyTransition.identity

    /// Левый край панели — у курсора; спрайт и текст выровнены по **общей вертикальной середине** (одна центральная линия).
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if viewModel.shouldShowCompanionSprite {
                    GremlinSpriteCharacterView(viewModel: viewModel)
                        .opacity(viewModel.companionPresentOpacity)
                        .scaleEffect(viewModel.companionPresentScale, anchor: UnitPoint(x: 0.5, y: 0.52))
                        .transition(Self.spriteMountTransition)
                } else {
                    Color.clear
                        .frame(width: 0, height: GremlinOverlaySpriteMetrics.displayHeight)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: viewModel.shouldShowCompanionSprite)

            Group {
                if viewModel.phase == .streaming, viewModel.visibleText.isEmpty {
                    TypingDotsView()
                } else if viewModel.phase == .textFalling,
                          !viewModel.visibleText.isEmpty,
                          viewModel.charFallOffsetsY.count == viewModel.visibleText.count {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(viewModel.visibleText.enumerated()), id: \.offset) { i, ch in
                            Text(String(ch))
                                .font(.system(size: 34, weight: .heavy))
                                .foregroundStyle(Self.lineGreen)
                                .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 1)
                                .offset(y: viewModel.charFallOffsetsY[i])
                                .opacity(
                                    viewModel.charFallOffsetsY[i] > 1
                                        ? max(0, 1 - Double(viewModel.charFallOffsetsY[i]) / 72)
                                        : 1
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .drawingGroup()
                } else if !viewModel.visibleText.isEmpty {
                    Text(viewModel.visibleText)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Self.lineGreen)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 1)
                }
            }
            .frame(minWidth: 0, maxWidth: textMaxWidth, alignment: .leading)
            .opacity(viewModel.bubbleOpacity)
            .offset(y: viewModel.bubbleOffsetY)
            .scaleEffect(viewModel.bubbleScale, anchor: .leading)
            .blur(radius: viewModel.bubbleBlurRadius)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.clear)
        .compositingGroup()
    }
}

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
                          viewModel.charFallOffsetsY.count == viewModel.visibleText.count,
                          viewModel.charFlowOffsetsX.count == viewModel.visibleText.count {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(viewModel.visibleText.enumerated()), id: \.offset) { i, ch in
                            SlimeFlowGlyph(
                                character: String(ch),
                                offsetY: viewModel.charFallOffsetsY[i],
                                driftX: viewModel.charFlowOffsetsX[i],
                                lineGreen: Self.lineGreen
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Слизистое стекание по буквам

/// Каждая буква тянет за собой градиентный «хвост», как капля слизи.
private struct SlimeFlowGlyph: View {
    let character: String
    let offsetY: CGFloat
    let driftX: CGFloat
    let lineGreen: Color

    private var p: Double {
        min(1.0, Double(max(0, offsetY)) / 176)
    }

    private var ribWidth: CGFloat {
        CGFloat(5.8 + 5.4 * sin(p * .pi))
    }

    /// Нитка слизи под глифом: растёт к середине движения, к концу растворяется.
    private var ribLength: CGFloat {
        CGFloat(16 + 88 * sin(p * .pi) * (1.08 - 0.28 * p))
    }

    private var stretchY: CGFloat {
        CGFloat(1.0 + 0.46 * sin(p * .pi))
    }

    private var squashX: CGFloat {
        CGFloat(1.0 - 0.16 * p)
    }

    private var glyphOpacity: Double {
        offsetY > 1.2 ? max(0.03, 1.0 - p * 0.97) : 1.0
    }

    private var meltBlur: CGFloat {
        CGFloat(6.2 * p * p)
    }

    private var blobSize: CGFloat {
        CGFloat(8 + 14 * sin(p * .pi))
    }

    var body: some View {
        Text(character)
            .font(.system(size: 34, weight: .heavy))
            .foregroundStyle(lineGreen)
            .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 1)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .top) {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    lineGreen.opacity(0.96),
                                    lineGreen.opacity(0.68),
                                    lineGreen.opacity(0.24),
                                    lineGreen.opacity(0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: ribWidth, height: ribLength)
                        .offset(x: driftX * 0.18, y: ribLength * 0.5 + 5)
                        .blur(radius: 2.4)

                    Circle()
                        .fill(lineGreen.opacity(0.42))
                        .frame(width: blobSize, height: blobSize * 0.92)
                        .offset(x: driftX * 0.34, y: ribLength + 6)
                        .blur(radius: 3.6)
                }
            }
            .scaleEffect(x: squashX, y: stretchY, anchor: .top)
            .offset(
                x: driftX + CGFloat(sin(Double(offsetY) / 18) * 4.6),
                y: offsetY
            )
            .opacity(glyphOpacity)
            .blur(radius: meltBlur)
    }
}

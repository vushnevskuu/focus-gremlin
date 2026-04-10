import SwiftUI

private enum CompanionOverlayTiming {
    /// Длительность фазы `dismissing` до затухания пузырька.
    static let dismissingSeconds: TimeInterval = 1.0
}

enum BubblePhase: Equatable {
    case idle
    case typingDots
    case streaming
    case holding
    case dismissing
}

/// Горизонтальная зона курсора на текущем экране (для выбора варианта «говорит»).
enum GremlinCursorZone: Equatable {
    case left
    case center
    case right
}

@MainActor
final class CompanionViewModel: ObservableObject {
    @Published var phase: BubblePhase = .idle
    @Published var visibleText: String = ""
    @Published var bubbleOpacity: Double = 0
    /// Новый цикл анимации кадров с начала при каждом сообщении.
    @Published private(set) var typingSpriteEpoch = UUID()
    /// Обновляется из оверлея по сглаженной позиции курсора.
    @Published private(set) var cursorZone: GremlinCursorZone = .center
    /// Вариант речи на время текущей доставки (по тексту или явной подсказке).
    @Published private(set) var deliverySpeechStyle: GremlinDeliverySpeechStyle = .spatial
    /// Сообщение от FocusEngine: акцентный кадр `final` во время набора/речи.
    @Published private(set) var distractionInterventionActive = false
    /// Пользователь в основном окне (настройки и т.п.) — оверлей не должен грузить CPU анимацией и постоянным layout.
    @Published private(set) var isInteractionFocusedOnMainAppWindow = false

    var isBusy: Bool { phase != .idle }

    func setMainWindowInteractionFocused(_ on: Bool) {
        guard on != isInteractionFocusedOnMainAppWindow else { return }
        isInteractionFocusedOnMainAppWindow = on
    }

    /// `normalizedScreenX` — 0…1 внутри `visibleFrame` экрана под курсором.
    func updateCursorZone(normalizedScreenX: CGFloat) {
        let next: GremlinCursorZone
        if normalizedScreenX < 0.34 {
            next = .left
        } else if normalizedScreenX > 0.66 {
            next = .right
        } else {
            next = .center
        }
        guard next != cursorZone else { return }
        cursorZone = next
    }

    private var deliveryTask: Task<Void, Never>?

    func cancelDelivery() {
        deliveryTask?.cancel()
        deliveryTask = nil
        resetVisuals()
    }

    private func resetVisuals() {
        phase = .idle
        visibleText = ""
        bubbleOpacity = 0
        deliverySpeechStyle = .spatial
        distractionInterventionActive = false
    }

    /// Живой цикл: точки → печать с редким «передумал» → удержание → исчезновение.
    /// `speechStyle`: если `nil`, стиль выводится из текста (`GremlinSpeechContext`).
    func runLiveDelivery(
        _ fullText: String,
        speechStyle: GremlinDeliverySpeechStyle? = nil,
        isDistractionIntervention: Bool = false
    ) async {
        deliveryTask?.cancel()
        deliveryTask = Task {
            await animate(fullText, speechStyle: speechStyle, isDistractionIntervention: isDistractionIntervention)
        }
        await deliveryTask?.value
    }

    private func animate(
        _ fullText: String,
        speechStyle: GremlinDeliverySpeechStyle?,
        isDistractionIntervention: Bool
    ) async {
        distractionInterventionActive = isDistractionIntervention
        deliverySpeechStyle = speechStyle ?? GremlinSpeechContext.inferSpeechStyle(for: fullText)
        typingSpriteEpoch = UUID()
        phase = .typingDots
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            bubbleOpacity = 1
        }
        try? await Task.sleep(nanoseconds: UInt64.random(in: 650_000_000...1_350_000_000))
        if Task.isCancelled { return }

        phase = .streaming
        visibleText = ""

        let chars = Array(fullText)
        let glitchPoint = chars.count > 28 ? Int(Double(chars.count) * 0.55) : -1
        var performedGlitch = false
        var idx = 0
        while idx < chars.count {
            if Task.isCancelled { return }
            let chunkEnd = min(idx + Int.random(in: 2...4), chars.count)
            for j in idx..<chunkEnd {
                if j == glitchPoint, !performedGlitch, Bool.random() {
                    performedGlitch = true
                    let back = Int.random(in: 4...9)
                    for _ in 0..<back {
                        if !visibleText.isEmpty { visibleText.removeLast() }
                        try? await Task.sleep(nanoseconds: 35_000_000)
                    }
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            }
            visibleText.append(contentsOf: chars[idx..<chunkEnd])
            idx = chunkEnd
            try? await Task.sleep(nanoseconds: UInt64.random(in: 22_000_000...42_000_000))
        }

        phase = .holding
        try? await Task.sleep(nanoseconds: UInt64.random(in: 4_000_000_000...6_500_000_000))
        if Task.isCancelled { return }

        phase = .dismissing
        /// Пауза в фазе `dismissing` (idle-анимация), затем затухание пузырька.
        let dismissNs = UInt64(CompanionOverlayTiming.dismissingSeconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: dismissNs)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.22)) {
            bubbleOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 240_000_000)
        resetVisuals()
    }
}

import SwiftUI

enum BubblePhase: Equatable {
    case idle
    case typingDots
    case streaming
    case holding
    case dismissing
}

@MainActor
final class CompanionViewModel: ObservableObject {
    @Published var phase: BubblePhase = .idle
    @Published var visibleText: String = ""
    @Published var bubbleOpacity: Double = 0
    /// Метка начала спрайта «улетания» (синхронно с `phase == .dismissing`).
    @Published private(set) var dismissSpriteStartedAt: Date?

    var isBusy: Bool { phase != .idle }

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
        dismissSpriteStartedAt = nil
    }

    /// Живой цикл: точки → печать с редким «передумал» → удержание → исчезновение.
    func runLiveDelivery(_ fullText: String) async {
        deliveryTask?.cancel()
        deliveryTask = Task {
            await animate(fullText)
        }
        await deliveryTask?.value
    }

    private func animate(_ fullText: String) async {
        phase = .typingDots
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            bubbleOpacity = 1
        }
        try? await Task.sleep(nanoseconds: UInt64.random(in: 650_000_000...1_350_000_000))
        if Task.isCancelled { return }

        phase = .streaming
        visibleText = ""

        let glitchPoint = fullText.count > 28 ? Int(Double(fullText.count) * 0.55) : -1
        var performedGlitch = false

        for (index, ch) in fullText.enumerated() {
            if Task.isCancelled { return }
            if index == glitchPoint, !performedGlitch, Bool.random() {
                performedGlitch = true
                let back = Int.random(in: 4...9)
                for _ in 0..<back {
                    if !visibleText.isEmpty { visibleText.removeLast() }
                    try? await Task.sleep(nanoseconds: 35_000_000)
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            visibleText.append(ch)
            try? await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000...34_000_000))
        }

        phase = .holding
        try? await Task.sleep(nanoseconds: UInt64.random(in: 4_000_000_000...6_500_000_000))
        if Task.isCancelled { return }

        dismissSpriteStartedAt = Date()
        phase = .dismissing
        // Спрайт «улетания» играет при полной непрозрачности, затем короткое затухание пузырька.
        let dismissNs = UInt64(GremlinDismissSheet.animationDuration * 1_000_000_000)
        try? await Task.sleep(nanoseconds: dismissNs)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.22)) {
            bubbleOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 240_000_000)
        resetVisuals()
    }
}

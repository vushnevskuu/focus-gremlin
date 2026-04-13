import SwiftUI

/// Состояние оверлея плевков вынесено из `CompanionViewModel`, чтобы изменения пятен **не триггерили**
/// `objectWillChange` у панели с гоблином и не грузили SwiftUI/layout спрайта.
@MainActor
final class GoblinSpitOverlayModel: ObservableObject {
    /// Согласовано с `CompanionOverlayTiming.spitDissolveDuration`.
    private static let dissolveDuration: TimeInterval = 1.45

    @Published private(set) var spitStains: [GoblinSpitStain] = []
    @Published private(set) var spitPanelContentSize: CGSize = .zero
    /// Идёт поочерёдное растворение после финала — не запускать `dissolveAll` из `syncFocusOverlayContext`.
    private(set) var sequentialDissolveInProgress = false

    var shouldShowSpitOverlay: Bool { !spitStains.isEmpty }

    private var spitCleanupTask: Task<Void, Never>?

    func setSpitPanelContentSize(_ size: CGSize) {
        guard size.width > 4, size.height > 4 else { return }
        guard size != spitPanelContentSize else { return }
        spitPanelContentSize = size
    }

    func cancelDissolveAndClear() {
        spitCleanupTask?.cancel()
        spitCleanupTask = nil
        sequentialDissolveInProgress = false
        spitStains = []
    }

    func appendStains(_ newStains: [GoblinSpitStain]) {
        let adjusted = nudgeSpitStainsForStacking(newStains)
        spitStains.append(contentsOf: adjusted)
        let cap = 6
        if spitStains.count > cap {
            spitStains.removeFirst(spitStains.count - cap)
        }
    }

    func dissolveAll(clearImmediately: Bool) {
        spitCleanupTask?.cancel()
        spitCleanupTask = nil
        sequentialDissolveInProgress = false
        guard !spitStains.isEmpty else { return }
        if clearImmediately {
            spitStains = []
            return
        }
        spitStains = spitStains.map { stain in
            var next = stain
            next.phase = .dissolving
            return next
        }
        spitCleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.dissolveDuration * 1_000_000_000)
            )
            guard let self, !Task.isCancelled else { return }
            self.spitStains = []
            self.spitCleanupTask = nil
        }
    }

    /// После полного проигрывания `final`: пятна остаются во время финала, затем уходят по одному (каскад).
    func beginSequentialDissolveAfterFinal(staggerSeconds: TimeInterval = 0.38) {
        spitCleanupTask?.cancel()
        spitCleanupTask = nil
        guard !spitStains.isEmpty else {
            sequentialDissolveInProgress = false
            return
        }
        sequentialDissolveInProgress = true
        let orderedIds = spitStains.map(\.id)
        spitCleanupTask = Task { @MainActor [weak self] in
            defer { self?.sequentialDissolveInProgress = false }
            guard let self else { return }
            for (idx, id) in orderedIds.enumerated() {
                if idx > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(staggerSeconds * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }
                self.markStainDissolving(id: id)
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.dissolveDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.spitStains = []
            self.spitCleanupTask = nil
        }
    }

    private func markStainDissolving(id: UUID) {
        guard let i = spitStains.firstIndex(where: { $0.id == id }) else { return }
        var s = spitStains[i]
        guard s.phase != .dissolving else { return }
        s.phase = .dissolving
        var copy = spitStains
        copy[i] = s
        spitStains = copy
    }

    /// Без слияния в одну «кашу»: при почти той же точке чуть сдвигаем новую каплю.
    private func nudgeSpitStainsForStacking(_ fresh: [GoblinSpitStain]) -> [GoblinSpitStain] {
        guard !fresh.isEmpty else { return fresh }
        guard spitPanelContentSize.width > 8, spitPanelContentSize.height > 8 else { return fresh }
        let w = spitPanelContentSize.width
        let h = spitPanelContentSize.height
        var occupied = spitStains
        var out: [GoblinSpitStain] = []
        out.reserveCapacity(fresh.count)
        for stain in fresh {
            var cur = stain
            var attempts = 0
            while attempts < 12 {
                let tooClose = occupied.contains { o in
                    let dx = (cur.normalizedX - o.normalizedX) * w
                    let dy = (cur.normalizedY - o.normalizedY) * h
                    let sep = max(20, (cur.width + o.width) * 0.24)
                    return hypot(dx, dy) < sep
                }
                if !tooClose { break }
                cur = GoblinSpitStain(
                    id: cur.id,
                    normalizedX: min(0.61, max(0.39, cur.normalizedX + CGFloat.random(in: -0.034...0.034))),
                    normalizedY: min(0.64, max(0.36, cur.normalizedY - CGFloat.random(in: 0.012...0.038))),
                    width: cur.width,
                    height: cur.height,
                    tailLength: cur.tailLength,
                    rotationDegrees: cur.rotationDegrees,
                    seed: cur.seed,
                    phase: cur.phase
                )
                attempts += 1
            }
            occupied.append(cur)
            out.append(cur)
        }
        return out
    }
}

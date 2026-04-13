import AppKit
import Combine
import MetalKit
import simd

private let kSpitDebugGridDefaultsKey = "FocusGremlinSpitDebugGrid"

/// Локальная симуляция капли: гравитация вниз, липкость, без вращения поля в шейдере.
private struct SalivaSimState {
    var offsetUV: SIMD2<Float>
    var vel: SIMD2<Float>
    var stickyUntil: CFTimeInterval
    var nextWobbleAt: CFTimeInterval
    var wobbleX: Float
    var tailStretch: Float
    var microLocal0: SIMD2<Float>
    var microLocal1: SIMD2<Float>
    var microLocal2: SIMD2<Float>
}

/// Рендер плевков через Metal (шейдер `SalivaMetalShader`); подкладывается в `spitPanel`.
@MainActor
final class SpitMetalContainerView: NSView {
    private let spitModel: GoblinSpitOverlayModel
    private let mtkView: MTKView
    private let renderer: SalivaMetalRenderer
    private var cancellables = Set<AnyCancellable>()
    /// Длина растворения — как `GoblinSpitOverlayModel` (private там).
    private let dissolveDuration: TimeInterval = 1.45
    private var dissolvingSince: [UUID: CFTimeInterval] = [:]
    private var simById: [UUID: SalivaSimState] = [:]
    private var lastSimMediaTime: CFTimeInterval?

    init(spitModel: GoblinSpitOverlayModel) {
        self.spitModel = spitModel
        self.mtkView = MTKView(frame: .zero)
        self.renderer = SalivaMetalRenderer()
        super.init(frame: .zero)
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mtkView)
        NSLayoutConstraint.activate([
            mtkView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mtkView.topAnchor.constraint(equalTo: topAnchor),
            mtkView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        renderer.attach(view: mtkView)
        renderer.beforeDraw = { [weak self] in
            self?.pushStainDataForCurrentFrame()
        }
        spitModel.$spitStains
            .combineLatest(spitModel.$spitPanelContentSize)
            .receive(on: RunLoop.main)
            .sink { [weak self] stains, _ in
                self?.onSpitModelChanged(stainCount: stains.count)
            }
            .store(in: &cancellables)
        onSpitModelChanged(stainCount: spitModel.spitStains.count)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:)") }

       /// Ограничение пикселей на полноэкранной панели: иначе 5K Retina × тяжёлый фрагмент дают просадки и гоблин «плывёт» за курсором.
    private static let maxSpitDrawablePixels: CGFloat = 1_420_000

    override func layout() {
        super.layout()
        SalivaMetalRenderer.configureTransparentMetalLayer(for: mtkView)
        updateMetalDrawableSizeIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        SalivaMetalRenderer.configureTransparentMetalLayer(for: mtkView)
        updateMetalDrawableSizeIfNeeded()
    }

    private func updateMetalDrawableSizeIfNeeded() {
        let scale = max(window?.backingScaleFactor ?? 2.0, 1.0)
        let ptW = bounds.width
        let ptH = bounds.height
        guard ptW > 2, ptH > 2 else { return }
        var pixW = ptW * scale
        var pixH = ptH * scale
        let area = pixW * pixH
        if area > Self.maxSpitDrawablePixels {
            let f = sqrt(Self.maxSpitDrawablePixels / area)
            pixW = max(320, floor(pixW * f))
            pixH = max(240, floor(pixH * f))
        }
        let newSize = CGSize(width: pixW, height: pixH)
        if abs(mtkView.drawableSize.width - newSize.width) > 0.5
            || abs(mtkView.drawableSize.height - newSize.height) > 0.5 {
            mtkView.drawableSize = newSize
        }
    }

    private func onSpitModelChanged(stainCount: Int) {
        let stains = spitModel.spitStains
        let w = spitModel.spitPanelContentSize.width
        let h = spitModel.spitPanelContentSize.height
        guard w > 8, h > 8, stainCount > 0, !stains.isEmpty else {
            let ids = Set(stains.map(\.id))
            dissolvingSince = dissolvingSince.filter { ids.contains($0.key) }
            simById = simById.filter { ids.contains($0.key) }
            lastSimMediaTime = nil
            renderer.clearToTransparent()
            renderer.setPaused(true)
            return
        }
        renderer.setPaused(false)
        updateDissolveTracking(stains: stains)
    }

    /// Каждый кадр Metal: актуальное растворение + один `commitStainData` (без лишних таймеров).
    private func pushStainDataForCurrentFrame() {
        let stains = spitModel.spitStains
        let w = spitModel.spitPanelContentSize.width
        let h = spitModel.spitPanelContentSize.height
        guard w > 8, h > 8, !stains.isEmpty else {
            renderer.commitStainData(
                viewport: CGSize(width: max(w, 1), height: max(h, 1)),
                stains: [],
                debugGridTint: false
            )
            return
        }
        updateDissolveTracking(stains: stains)
        let now = CACurrentMediaTime()
        let dt = Float(min(0.08, max(0, now - (lastSimMediaTime ?? now))))
        lastSimMediaTime = now
        let blobData = stains.map { stainBlob(from: $0, panelW: w, panelH: h, now: now, dt: dt) }
        let debug = UserDefaults.standard.bool(forKey: kSpitDebugGridDefaultsKey)
        renderer.commitStainData(
            viewport: CGSize(width: w, height: h),
            stains: blobData,
            debugGridTint: debug
        )
    }

    private func updateDissolveTracking(stains: [GoblinSpitStain]) {
        let now = CACurrentMediaTime()
        let active = Set(stains.map(\.id))
        dissolvingSince = dissolvingSince.filter { active.contains($0.key) }
        for s in stains where s.phase == .dissolving {
            if dissolvingSince[s.id] == nil {
                dissolvingSince[s.id] = now
            }
        }
    }

    private func dissolveProgress(for id: UUID, phase: GoblinSpitStainPhase) -> Float {
        if phase == .fresh { return 0 }
        guard let start = dissolvingSince[id] else { return 0 }
        let p = (CACurrentMediaTime() - start) / dissolveDuration
        return Float(min(1, max(0, p)))
    }

    private func stainBlob(from stain: GoblinSpitStain, panelW w: CGFloat, panelH h: CGFloat, now: CFTimeInterval, dt: Float) -> StainBlobData {
        let boxW = stain.width * 2.45
        let boxH = stain.height + stain.tailLength * 1.62 + 136
        let cx = min(max(stain.normalizedX * w, boxW * 0.5), max(boxW * 0.5, w - boxW * 0.5))
        let cy = min(max(stain.normalizedY * h, boxH * 0.5), max(boxH * 0.5, h - boxH * 0.5))
        let baseU = Float(cx / w)
        let baseV = Float(cy / h)
        let halfAX = Float((stain.width * 0.5 / w) * 2.35)
        let halfAY = Float((stain.height * 0.5 / h) * 2.05)
        let tailUV = Float(stain.tailLength / max(h, 1)) * 1.75 + 0.08
        let rot = Float(stain.rotationDegrees * (.pi / 180))
        let seedF = Float(abs(stain.seed % 100_009)) * 0.01
        let d = dissolveProgress(for: stain.id, phase: stain.phase)
        let thick: Float = stain.phase == .dissolving ? max(0.35, 1 - d) : 1

        let sim = stepSimulation(for: stain, now: now, dt: dt)
        let u = min(0.97, max(0.03, baseU + sim.offsetUV.x))
        let v = min(0.97, max(0.03, baseV + sim.offsetUV.y))

        let s = sin(rot)
        let c = cos(rot)
        let m0 = rotateMicro(sim.microLocal0, c: c, s: s, halfAX: halfAX, halfAY: halfAY)
        let m1 = rotateMicro(sim.microLocal1, c: c, s: s, halfAX: halfAX, halfAY: halfAY)
        let m2 = rotateMicro(sim.microLocal2, c: c, s: s, halfAX: halfAX, halfAY: halfAY)

        return StainBlobData(
            center: SIMD2(u, v),
            halfAxes: SIMD2(max(halfAX, 1e-4), max(halfAY, 1e-4)),
            rotation: rot,
            tailUV: tailUV,
            thicknessMul: thick,
            dissolve: d,
            seed: seedF,
            tailStretch: sim.tailStretch,
            micro0: m0,
            micro1: m1,
            micro2: m2,
            padx: 0
        )
    }

    private func rotateMicro(_ local: SIMD2<Float>, c: Float, s: Float, halfAX: Float, halfAY: Float) -> SIMD2<Float> {
        let lx = local.x * halfAX * 2.8
        let ly = local.y * halfAY * 2.8
        return SIMD2(c * lx - s * ly, s * lx + c * ly)
    }

    private func bootstrapSim(seed: Int) -> SalivaSimState {
        func ml(_ a: Int, _ b: Int) -> SIMD2<Float> {
            let x = Float((seed &* 127 &+ a &* 911) % 10_009) / 10_009.0
            let y = Float((seed &* 31 &+ b &* 503) % 9973) / 9973.0
            return SIMD2((x - 0.5) * 0.95, (y - 0.42) * 0.85 - 0.12)
        }
        return SalivaSimState(
            offsetUV: .zero,
            vel: SIMD2(Float.random(in: -0.0022...0.0022), Float.random(in: 0.005...0.014)),
            stickyUntil: 0,
            nextWobbleAt: CACurrentMediaTime() + Double.random(in: 0.18...0.55),
            wobbleX: 0,
            tailStretch: 0.12,
            microLocal0: ml(1, 2),
            microLocal1: ml(3, 4),
            microLocal2: ml(5, 6)
        )
    }

    private func stepSimulation(for stain: GoblinSpitStain, now: CFTimeInterval, dt: Float) -> SalivaSimState {
        let id = stain.id
        if simById[id] == nil {
            simById[id] = bootstrapSim(seed: stain.seed)
        }
        guard var st = simById[id] else { return bootstrapSim(seed: stain.seed) }

        let g: Float = 0.024
        if now < st.stickyUntil {
            st.vel.x *= pow(0.9, dt * 60)
            st.vel.y *= pow(0.55, dt * 60)
        } else {
            st.vel.y += g * dt
            st.vel.y = min(st.vel.y, 0.042)
            st.vel *= pow(0.985, dt * 60)
            if Double.random(in: 0...1) < Double(dt) * 0.65 * 0.012 {
                st.stickyUntil = now + Double.random(in: 0.06...0.2)
            }
        }

        if now >= st.nextWobbleAt {
            st.nextWobbleAt = now + Double.random(in: 0.25...0.7)
            st.wobbleX = Float.random(in: -0.0028...0.0028)
        }
        st.wobbleX *= pow(0.9, dt * 60)

        st.offsetUV.x += (st.vel.x + st.wobbleX) * dt
        st.offsetUV.y += st.vel.y * dt

        let maxOff: Float = 0.072
        let len = simd_length(st.offsetUV)
        if len > maxOff {
            st.offsetUV *= maxOff / len
        }

        st.tailStretch = min(1.38, st.tailStretch + st.vel.y * dt * 2.6)
        let lag: Float = 0.38
        st.microLocal0.y -= st.vel.y * dt * lag * 0.35
        st.microLocal1.y -= st.vel.y * dt * lag * 0.28
        st.microLocal2.y -= st.vel.y * dt * lag * 0.32

        simById[id] = st
        return st
    }
}

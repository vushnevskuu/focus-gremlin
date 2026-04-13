import AppKit
import SwiftUI

// MARK: - Tunables (мокрое стекло: резкая маска, без теней-пятен; блик без тумана)

/// `UserDefaults` = true: под плевками рисуется шахматная сетка (оценка прозрачности на контрасте).
private let kSpitDebugGridDefaultsKey = "FocusGremlinSpitDebugGrid"

private enum GoblinSpitRenderParams {
    /// Blur маски только для слияния форм — чем меньше, тем меньше «тумана».
    static let maskBlurRadius: CGFloat = 0.68
    static let maskAlphaThreshold: CGFloat = 0.61
    /// Блики без размытия (0 = острые полосы).
    static let specularBlur: CGFloat = 0.0
    static let dissolveBlurMax: CGFloat = 1.5
    /// Медленнее ползёт вниз (липкая вязкость).
    static let oozeSpringResponse: Double = 0.72
    static let oozeSpringDamping: Double = 0.93
    static let backdropOverscan: CGFloat = 46
}

enum GoblinSpitStainPhase: Equatable {
    case fresh
    case dissolving
}

struct GoblinSpitStain: Identifiable, Equatable {
    let id: UUID
    let normalizedX: CGFloat
    let normalizedY: CGFloat
    let width: CGFloat
    let height: CGFloat
    let tailLength: CGFloat
    let rotationDegrees: Double
    let seed: Int
    var phase: GoblinSpitStainPhase = .fresh
}

struct GoblinSpitOverlayView: View {
    @ObservedObject var spitModel: GoblinSpitOverlayModel

    var body: some View {
        let dim = spitLayoutDimensions()
        spitZStack(width: dim.width, height: dim.height)
            .frame(width: dim.width, height: dim.height, alignment: .topLeading)
            .background(Color.clear)
            .allowsHitTesting(false)
    }

    /// Размер видимой области экрана: из модели (после `updateSpitPanel`) или сразу из `NSScreen`, без `GeometryReader` (у хостинга он часто даёт неверный первый проход).
    private func spitLayoutDimensions() -> CGSize {
        let s = spitModel.spitPanelContentSize
        if s.width > 8, s.height > 8 {
            return s
        }
        if let fromScreen = Self.visibleFrameSizeForMouse() {
            return fromScreen
        }
        if let main = NSScreen.main {
            let f = main.visibleFrame
            return CGSize(width: max(f.width, 1), height: max(f.height, 1))
        }
        return CGSize(width: 800, height: 600)
    }

    private static func visibleFrameSizeForMouse() -> CGSize? {
        let mouse = NSEvent.mouseLocation
        let nsPoint = NSPoint(x: mouse.x, y: mouse.y)
        let screen = NSScreen.screens.first { NSMouseInRect(nsPoint, $0.frame, false) } ?? NSScreen.main
        guard let s = screen else { return nil }
        let f = s.visibleFrame
        guard f.width > 8, f.height > 8 else { return nil }
        return CGSize(width: f.width, height: f.height)
    }

    @ViewBuilder
    private func spitZStack(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if UserDefaults.standard.bool(forKey: kSpitDebugGridDefaultsKey) {
                SpitMaterialDebugGrid()
                    .frame(width: w, height: h)
                    .allowsHitTesting(false)
            }
            // Старые ниже, новые сверху — как наслоение капель, без перерисовки в одну мета-форму.
            ForEach(Array(spitModel.spitStains.enumerated()), id: \.element.id) { index, stain in
                let boxW = stain.width * 2.45
                let boxH = stain.height + stain.tailLength * 1.62 + 136
                let cx = min(max(stain.normalizedX * w, boxW * 0.5), max(boxW * 0.5, w - boxW * 0.5))
                let cy = min(max(stain.normalizedY * h, boxH * 0.5), max(boxH * 0.5, h - boxH * 0.5))
                GoblinSpitStainView(stain: stain)
                    .frame(width: boxW, height: boxH)
                    .position(x: cx, y: cy)
                    .zIndex(Double(index))
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }
}

/// Контрастная сетка под плевками: видно прозрачность и «стекло», не белый лист.
private struct SpitMaterialDebugGrid: View {
    private let cell: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? Color(white: 0.58) : Color(white: 0.2))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Живой backdrop-слой: системный glass/material реально читает фон под прозрачной `NSPanel`.
private struct GoblinBackdropGlassView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var emphasized = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.blendingMode = .behindWindow
        view.material = material
        view.isEmphasized = emphasized
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
        nsView.blendingMode = .behindWindow
        nsView.material = material
        nsView.isEmphasized = emphasized
    }
}

private struct GoblinSpitStainView: View {
    let stain: GoblinSpitStain

    @State private var impactScale: CGFloat = 0.16
    @State private var alpha: Double = 0.96
    @State private var sagY: CGFloat = -14
    @State private var swayX: CGFloat = 0
    /// Сразу почти полный хвост — иначе анимация роста выглядит как «улет вниз».
    @State private var tailReveal: CGFloat = 0.82
    @State private var oozeSlide: CGFloat = 0
    @State private var oozeSpread: CGFloat = 0
    @State private var oozeLeanX: CGFloat = 0
    @State private var dissolveSink: CGFloat = 0
    @State private var dissolveBlur: CGFloat = 0
    /// Растяжение «капли под скоростью» (ось X сжимается, Y тянется вниз) — как sclX/sclY в sliding-фазе three.js.
    @State private var dripStretchX: CGFloat = 1
    @State private var dripStretchY: CGFloat = 1
    @State private var dripRotZ: Double = 0
    /// Короткая фаза «набухания» у нижнего края перед стабилизацией (dripping hang).
    @State private var hangBulge: CGFloat = 0

    private struct GoblinSpitLobeSpec: Hashable {
        let id: Int
        let xOffset: CGFloat
        let yOffset: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private struct GoblinSpitDripSpec: Hashable {
        let id: Int
        let xOffset: CGFloat
        let width: CGFloat
        let length: CGFloat
        let sway: CGFloat
        let bulbInflation: CGFloat
        let neckTaper: CGFloat
        /// Асимметрия нижней капли: не «иконка».
        let bulbSkew: CGFloat
        let opacity: Double
    }

    private struct GoblinSpitSatelliteSpec: Hashable {
        let id: Int
        let xOffset: CGFloat
        let yOffset: CGFloat
        let width: CGFloat
        let height: CGFloat
        let opacity: Double
    }

    /// Влажная плёнка: насыщенный жёлто-зелёный, заметнее на экране.
    private var salivaBaseClear: Color {
        Color(red: 0.38, green: 0.82, blue: 0.36).opacity(0.28)
    }

    private var salivaTint: Color {
        Color(red: 0.14, green: 0.62, blue: 0.30).opacity(0.46)
    }

    /// Плотные зоны: глубокий изумрудно-зелёный.
    private var salivaThick: Color {
        Color(red: 0.05, green: 0.48, blue: 0.26).opacity(0.78)
    }

    private var salivaThinFilm: Color {
        Color(red: 0.58, green: 0.88, blue: 0.52).opacity(0.18)
    }

    private var blobShape: GoblinSpitBlobShape {
        GoblinSpitBlobShape(
            topInset: seededScalar(201, range: 0.07...0.14),
            leftInset: seededScalar(202, range: 0.09...0.18),
            rightInset: seededScalar(203, range: 0.08...0.16),
            bottomSag: seededScalar(204, range: 0.88...0.97),
            asymmetry: seededScalar(205, range: -0.18...0.18)
        )
    }

    private var surfaceFrameWidth: CGFloat {
        stain.width * (1.62 + oozeSpread * 0.18)
    }

    private var surfaceFrameHeight: CGFloat {
        stain.height + stain.tailLength * max(1, tailReveal) + 88
    }

    private var lobeSpecs: [GoblinSpitLobeSpec] {
        [
            GoblinSpitLobeSpec(
                id: 0,
                xOffset: -stain.width * seededScalar(210, range: 0.22...0.30),
                yOffset: stain.height * seededScalar(211, range: 0.08...0.18),
                width: stain.width * seededScalar(212, range: 0.30...0.42),
                height: stain.height * seededScalar(213, range: 0.40...0.58)
            ),
            GoblinSpitLobeSpec(
                id: 1,
                xOffset: stain.width * seededScalar(214, range: 0.18...0.28),
                yOffset: stain.height * seededScalar(215, range: 0.04...0.14),
                width: stain.width * seededScalar(216, range: 0.26...0.38),
                height: stain.height * seededScalar(217, range: 0.38...0.54)
            ),
            GoblinSpitLobeSpec(
                id: 2,
                xOffset: stain.width * seededScalar(218, range: -0.06...0.08),
                yOffset: -stain.height * seededScalar(219, range: 0.10...0.18),
                width: stain.width * seededScalar(220, range: 0.24...0.34),
                height: stain.height * seededScalar(221, range: 0.24...0.36)
            )
        ]
    }

    private var dripSpecs: [GoblinSpitDripSpec] {
        let primary = GoblinSpitDripSpec(
            id: 0,
            xOffset: seededScalar(61, range: -stain.width * 0.16...stain.width * 0.08),
            width: seededScalar(62, range: max(14, stain.width * 0.08)...max(24, stain.width * 0.13)),
            length: stain.tailLength * seededScalar(63, range: 0.82...1.04),
            sway: seededScalar(64, range: -0.18...0.18),
            bulbInflation: seededScalar(65, range: 1.04...1.32),
            neckTaper: seededScalar(66, range: 0.54...0.82),
            bulbSkew: seededScalar(79, range: -0.42...0.42),
            opacity: 0.98
        )

        var result = [primary]
        if abs(stain.seed % 2) == 0 {
            let side: CGFloat = primary.xOffset >= 0 ? -1 : 1
            result.append(
                GoblinSpitDripSpec(
                    id: 1,
                    xOffset: side * seededScalar(67, range: stain.width * 0.08...stain.width * 0.22),
                    width: seededScalar(68, range: max(10, stain.width * 0.06)...max(18, stain.width * 0.10)),
                    length: stain.tailLength * seededScalar(69, range: 0.42...0.72),
                    sway: side * seededScalar(70, range: 0.04...0.14),
                    bulbInflation: seededScalar(71, range: 0.84...1.10),
                    neckTaper: seededScalar(72, range: 0.50...0.76),
                    bulbSkew: seededScalar(80, range: -0.38...0.38),
                    opacity: 0.92
                )
            )
        }
        if abs(stain.seed % 5) == 0 {
            result.append(
                GoblinSpitDripSpec(
                    id: 2,
                    xOffset: seededScalar(73, range: -stain.width * 0.07...stain.width * 0.07),
                    width: seededScalar(74, range: max(6, stain.width * 0.04)...max(10, stain.width * 0.06)),
                    length: stain.tailLength * seededScalar(75, range: 0.22...0.40),
                    sway: seededScalar(76, range: -0.08...0.08),
                    bulbInflation: seededScalar(77, range: 0.72...0.94),
                    neckTaper: seededScalar(78, range: 0.46...0.68),
                    bulbSkew: seededScalar(81, range: -0.5...0.5),
                    opacity: 0.78
                )
            )
        }
        return result
    }

    private var satelliteSpecs: [GoblinSpitSatelliteSpec] {
        let count = 1 + abs(stain.seed % 3)
        return (0..<count).map { index in
            GoblinSpitSatelliteSpec(
                id: index,
                xOffset: seededScalar(230 + index, range: -stain.width * 0.26...stain.width * 0.24),
                yOffset: seededScalar(240 + index, range: -stain.height * 0.04...stain.height * 0.34),
                width: seededScalar(250 + index, range: stain.width * 0.04...stain.width * 0.16),
                height: seededScalar(260 + index, range: stain.height * 0.06...stain.height * 0.24),
                opacity: Double(seededScalar(270 + index, range: 0.62...0.90))
            )
        }
    }

    private var oozePhysicsAnchor: UnitPoint {
        UnitPoint(x: 0.5, y: 0.14)
    }

    var body: some View {
        ZStack {
            salivaMaterialView
        }
        .frame(width: surfaceFrameWidth, height: surfaceFrameHeight)
        .scaleEffect(
            x: dripStretchX * (1 + hangBulge * 0.11),
            y: dripStretchY * (1 - hangBulge * 0.07),
            anchor: oozePhysicsAnchor
        )
        .rotationEffect(.degrees(stain.rotationDegrees + dripRotZ))
        .scaleEffect(impactScale)
        .offset(x: swayX + oozeLeanX, y: sagY + oozeSlide + dissolveSink)
        .opacity(alpha)
        .blur(radius: dissolveBlur)
        .compositingGroup()
        .onAppear {
            animateImpact()
            if stain.phase == .dissolving {
                animateDissolve()
            }
        }
        .onChange(of: stain.phase) { _, phase in
            if phase == .dissolving {
                animateDissolve()
            }
        }
    }

    /// Оптика: прозрачное тело + локальная «толщина» + имитация IOR + Fresnel + острые блики (без теней-пятен).
    private var salivaMaterialView: some View {
        let mask = gooMaskView
        return ZStack {
            residueTrailLayer
            ZStack {
                backdropLensLayers
                baseGelFilm
                refractionTintLayer
                thicknessVariationsLayer
                densityCoreLayer
                chromaticEdgeFringe
                fresnelTopHighlightLayer
                specularHighlightLayer
                glassClearcoatRim
            }
            .mask(mask)
        }
        .frame(width: surfaceFrameWidth, height: surfaceFrameHeight)
    }

    /// Два сдвинутых live-backdrop слоя дают не просто blur, а ощущение преломления стеклянной слизи.
    private var backdropLensLayers: some View {
        let overscan = GoblinSpitRenderParams.backdropOverscan
        return ZStack {
            GoblinBackdropGlassView(material: .hudWindow)
                .frame(width: surfaceFrameWidth + overscan, height: surfaceFrameHeight + overscan)
                .offset(
                    x: seededScalar(440, range: -7...7) + oozeLeanX * 0.28,
                    y: seededScalar(441, range: -6...8) + oozeSlide * 0.14
                )
                .opacity(0.92)

            GoblinBackdropGlassView(material: .underWindowBackground)
                .frame(width: surfaceFrameWidth + overscan * 1.2, height: surfaceFrameHeight + overscan * 1.2)
                .offset(
                    x: seededScalar(442, range: -10...10) - oozeLeanX * 0.22,
                    y: seededScalar(443, range: -8...10) + oozeSlide * 0.08
                )
                .blendMode(.plusLighter)
                .opacity(0.54)

            GoblinBackdropGlassView(material: .menu, emphasized: true)
                .frame(width: stain.width * 1.02, height: stain.height * 0.92 + stain.tailLength * 0.44)
                .offset(
                    x: seededScalar(444, range: -4...4),
                    y: stain.height * 0.16 + oozeSlide * 0.05
                )
                .opacity(0.32)
                .mask(coreThicknessMask)
        }
        .compositingGroup()
    }

    private var baseGelFilm: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        salivaThinFilm.opacity(0.88),
                        salivaBaseClear.opacity(0.94),
                        salivaTint.opacity(0.84),
                        salivaTint.opacity(0.62),
                        salivaThinFilm.opacity(0.36)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blendMode(.screen)
    }

    /// Горизонтальный/радиальный градиент как слабый IOR (без размытия маски).
    private var refractionTintLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.82, blue: 0.38).opacity(0.32),
                    Color(red: 0.14, green: 0.58, blue: 0.28).opacity(0.12),
                    Color(red: 0.44, green: 0.76, blue: 0.30).opacity(0.26)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            RadialGradient(
                colors: [
                    Color(red: 0.34, green: 0.92, blue: 0.42).opacity(0.34),
                    Color(red: 0.16, green: 0.52, blue: 0.24).opacity(0.10)
                ],
                center: UnitPoint(x: 0.48, y: 0.38),
                startRadius: 2,
                endRadius: stain.width * 0.95
            )
        }
        .blendMode(.softLight)
    }

    /// Толщина: softLight/overlay — светлее в густоте, хвосты остаются тонкими по геометрии маски.
    private var thicknessVariationsLayer: some View {
        ZStack {
            Ellipse()
                .fill(salivaThick.opacity(0.96))
                .frame(width: stain.width * 0.36, height: stain.height * 0.2)
                .offset(x: seededScalar(180, range: -stain.width * 0.06...stain.width * 0.04), y: -stain.height * 0.04)
            ForEach(dripSpecs, id: \.id) { drip in
                let reveal = max(0.16, tailReveal)
                let effectiveLength = max(18, drip.length * reveal)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                salivaThick.opacity(drip.id == 0 ? 0.72 : 0.52),
                                salivaThick.opacity(drip.id == 0 ? 0.38 : 0.24)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(2.2, drip.width * 0.16), height: effectiveLength * 0.48)
                    .offset(
                        x: drip.xOffset + drip.bulbSkew * drip.width * 0.12,
                        y: stain.height * 0.56 + effectiveLength * 0.24
                    )
            }
        }
        .blendMode(.softLight)
    }

    /// Плотные ядра и шея хвостов: толще, темнее и зеленее, чем водяная капля.
    private var densityCoreLayer: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            salivaThick.opacity(0.72),
                            salivaThick.opacity(0.94),
                            Color(red: 0.06, green: 0.36, blue: 0.20).opacity(0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(coreThicknessMask)
                .blendMode(.multiply)

            RadialGradient(
                colors: [
                    Color(red: 0.72, green: 0.96, blue: 0.54).opacity(0.36),
                    Color.clear
                ],
                center: UnitPoint(x: 0.46, y: 0.26),
                startRadius: 3,
                endRadius: stain.width * 0.52
            )
            .mask(coreThicknessMask)
                .blendMode(.screen)
        }
    }

    /// Мягкий остаточный след от уже стекшей массы — вне текущей кромки, как слизистый мазок на стекле.
    private var residueTrailLayer: some View {
        ZStack {
            ForEach(dripSpecs, id: \.id) { drip in
                let reveal = max(0.22, tailReveal)
                let effectiveLength = max(20, drip.length * reveal)
                let residueHeight = effectiveLength * (0.46 + oozeSlide / 260)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                salivaTint.opacity(0.06),
                                salivaTint.opacity(0.14),
                                salivaThick.opacity(0.07),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(2, drip.width * 0.20), height: residueHeight)
                    .offset(
                        x: drip.xOffset + drip.bulbSkew * drip.width * 0.10,
                        y: stain.height * 0.72 + residueHeight * 0.16
                    )
                    .blur(radius: 0.7)
                    .opacity(min(0.7, Double(0.16 + oozeSlide / 180)))
            }
        }
    }

    private var coreThicknessMask: some View {
        ZStack {
            Ellipse()
                .fill(Color.white)
                .frame(width: stain.width * 0.74, height: stain.height * 0.62)
                .offset(x: seededScalar(445, range: -stain.width * 0.03...stain.width * 0.03), y: -stain.height * 0.02)

            ForEach(dripSpecs, id: \.id) { drip in
                let reveal = max(0.18, tailReveal)
                let effectiveLength = max(18, drip.length * reveal)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(drip.id == 0 ? 1 : 0.82))
                    .frame(width: max(2.6, drip.width * 0.22), height: effectiveLength * 0.60)
                    .offset(
                        x: drip.xOffset + drip.bulbSkew * drip.width * 0.12,
                        y: stain.height * 0.54 + effectiveLength * 0.24
                    )
            }
        }
    }

    /// Тонкие смещённые обводки — «преломление» у кромки без drop shadow.
    private var chromaticEdgeFringe: some View {
        ZStack {
            Ellipse()
                .strokeBorder(Color(red: 0.18, green: 0.96, blue: 0.48).opacity(0.46), lineWidth: 1.0)
                .frame(width: stain.width * (1.02 + oozeSpread * 0.06), height: stain.height * (0.88 + oozeSpread * 0.04))
                .offset(x: -0.7, y: -stain.height * 0.04)
            Ellipse()
                .strokeBorder(Color(red: 0.72, green: 0.94, blue: 0.42).opacity(0.28), lineWidth: 0.8)
                .frame(width: stain.width * (1.02 + oozeSpread * 0.06), height: stain.height * (0.88 + oozeSpread * 0.04))
                .offset(x: 0.65, y: -stain.height * 0.04)
        }
        .blendMode(.screen)
    }

    /// Светлый Fresnel у верхней зоны (не тёмный мениск).
    private var fresnelTopHighlightLayer: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.38),
                        Color.white.opacity(0.06),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.16)
                )
            )
            .blendMode(.screen)
    }

    /// Острые влажные блики (без размытия).
    private var specularHighlightLayer: some View {
        ZStack {
            ForEach(dripSpecs, id: \.id) { drip in
                let reveal = max(0.16, tailReveal)
                let effectiveLength = max(18, drip.length * reveal)
                let specW = max(0.9, drip.width * 0.065)
                let yPos = stain.height * 0.5 + effectiveLength * 0.22
                let xBase = drip.xOffset - drip.width * 0.14 + drip.bulbSkew * 3
                Capsule(style: .continuous)
                    .fill(Color(red: 0.98, green: 0.995, blue: 1).opacity(drip.id == 0 ? 0.72 : 0.52))
                    .frame(width: specW, height: effectiveLength * 0.34)
                    .blur(radius: GoblinSpitRenderParams.specularBlur)
                    .offset(x: xBase, y: yPos)
                    .blendMode(.screen)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(drip.id == 0 ? 0.95 : 0.78))
                    .frame(width: max(0.5, specW * 0.42), height: effectiveLength * 0.32)
                    .offset(x: xBase - specW * 0.22, y: yPos)
                    .blendMode(.screen)
            }
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.62))
                .frame(width: stain.width * 0.22, height: max(1.5, stain.height * 0.022))
                .rotationEffect(.degrees(Double(seededScalar(12, range: -14...10))))
                .offset(
                    x: seededScalar(13, range: -stain.width * 0.06...stain.width * 0.04),
                    y: -stain.height * 0.06
                )
                .blendMode(.screen)
        }
    }

    /// Кромка: сильный Fresnel по периметру + узкий блик без blur-ореола.
    private var glassClearcoatRim: some View {
        ZStack {
            Ellipse()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.72),
                            Color.white.opacity(0.38),
                            salivaTint.opacity(0.52),
                            Color.white.opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.05
                )
                .frame(width: stain.width * (1.0 + oozeSpread * 0.08), height: stain.height * (0.84 + oozeSpread * 0.05))
                .offset(y: -stain.height * 0.045)
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.48), Color.white.opacity(0.12), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: max(2.5, stain.width * 0.055), height: stain.height * 0.38)
                .offset(x: -stain.width * 0.16, y: -stain.height * 0.02)
                .blendMode(.screen)
        }
    }

    private var gooMaskView: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            context.addFilter(.blur(radius: GoblinSpitRenderParams.maskBlurRadius))
            context.addFilter(.alphaThreshold(min: GoblinSpitRenderParams.maskAlphaThreshold, color: .white))
            context.drawLayer { layer in
                let pool = poolRect(in: size)
                layer.fill(blobShape.path(in: pool), with: .color(.white))

                // Брызги у верхнего удара — не один мягкий овал.
                for i in 0..<6 {
                    let rx = seededScalar(300 + i, range: pool.width * 0.08...pool.width * 0.42)
                    let ry = seededScalar(310 + i, range: pool.height * 0.03...pool.height * 0.11)
                    let ox = seededScalar(320 + i, range: -pool.width * 0.28...pool.width * 0.28)
                    let oy = seededScalar(330 + i, range: pool.minY - pool.height * 0.02...pool.minY + pool.height * 0.12)
                    let spatter = CGRect(
                        x: pool.midX + ox - rx * 0.5,
                        y: oy,
                        width: rx,
                        height: ry
                    )
                    layer.fill(Path(ellipseIn: spatter), with: .color(.white.opacity(Double(seededScalar(340 + i, range: 0.55...0.95)))))
                }

                for lobe in lobeSpecs {
                    layer.fill(Path(ellipseIn: lobeRect(for: lobe, in: pool)), with: .color(.white))
                }

                for drip in dripSpecs {
                    let dripRect = dripRect(for: drip, in: pool)
                    let shoulder = CGRect(
                        x: dripRect.midX - drip.width * 0.70,
                        y: pool.maxY - drip.width * 0.32,
                        width: drip.width * 1.40,
                        height: drip.width * 0.84
                    )
                    layer.fill(Path(ellipseIn: shoulder), with: .color(.white))
                    layer.fill(
                        GoblinSpitDripShape(
                            sway: drip.sway,
                            bulbInflation: drip.bulbInflation,
                            neckTaper: drip.neckTaper,
                            bulbSkew: drip.bulbSkew
                        )
                        .path(in: dripRect),
                        with: .color(.white.opacity(drip.opacity))
                    )
                }

                for satellite in satelliteSpecs {
                    layer.fill(
                        Path(ellipseIn: satelliteRect(for: satellite, in: pool)),
                        with: .color(.white.opacity(satellite.opacity))
                    )
                }
            }
        }
        .frame(width: surfaceFrameWidth, height: surfaceFrameHeight)
        .allowsHitTesting(false)
    }

    private func animateImpact() {
        let drift = seededScalar(51, range: -5...5)
        let targetSlide = seededScalar(53, range: 22...44)
        let spread = seededScalar(54, range: 0.10...0.22)
        let lean = seededScalar(55, range: -5...5)
        let tailCap = seededScalar(56, range: 1.04...1.14)
        let oozeDuration = TimeInterval(seededScalar(52, range: 4.2...6.0))

        withAnimation(
            .spring(
                response: GoblinSpitRenderParams.oozeSpringResponse,
                dampingFraction: GoblinSpitRenderParams.oozeSpringDamping
            )
        ) {
            impactScale = 1
            alpha = 1
            sagY = 0
            dripStretchX = 1
            dripStretchY = 1
            dripRotZ = 0
            hangBulge = 0
        }
        withAnimation(.easeOut(duration: 0.38)) {
            tailReveal = 1
        }
        withAnimation(.easeInOut(duration: oozeDuration).delay(0.12)) {
            oozeSlide = targetSlide
            oozeSpread = spread
            oozeLeanX = lean
            tailReveal = tailCap
            swayX = drift * 0.65
        }
        // Лёгкое вытяжение без рывков — один короткий возврат к 1.
        withAnimation(
            .spring(response: GoblinSpitRenderParams.oozeSpringResponse, dampingFraction: GoblinSpitRenderParams.oozeSpringDamping)
                .delay(0.12 + oozeDuration * 0.45)
        ) {
            dripStretchX = 0.98
            dripStretchY = 1.05
            dripRotZ = Double(drift) * 0.12
        }
        withAnimation(
            .spring(response: GoblinSpitRenderParams.oozeSpringResponse * 1.12, dampingFraction: GoblinSpitRenderParams.oozeSpringDamping)
                .delay(0.12 + oozeDuration * 0.72)
        ) {
            dripStretchX = 1
            dripStretchY = 1.02
            dripRotZ = Double(drift) * 0.04
        }
        withAnimation(.easeInOut(duration: 0.55).delay(0.08 + oozeDuration * 0.5)) {
            hangBulge = 0.45
        }
        withAnimation(
            .spring(response: GoblinSpitRenderParams.oozeSpringResponse, dampingFraction: GoblinSpitRenderParams.oozeSpringDamping)
                .delay(0.45 + oozeDuration * 0.55)
        ) {
            hangBulge = 0
        }
    }

    private func animateDissolve() {
        withAnimation(.easeInOut(duration: 1.35)) {
            alpha = 0
            impactScale = 0.72
            dissolveSink = 26 + stain.tailLength * 0.24
            dissolveBlur = GoblinSpitRenderParams.dissolveBlurMax
            tailReveal = 1.28
            oozeSlide += 12
            dripStretchX = 1.1
            dripStretchY = 0.88
            dripRotZ = 0
            hangBulge = 0
        }
    }

    private func poolRect(in size: CGSize) -> CGRect {
        let width = stain.width * (1 + oozeSpread * 0.18)
        let height = stain.height * seededScalar(280, range: 0.78...0.90) * (1 - oozeSpread * 0.10)
        return CGRect(
            x: (size.width - width) * 0.5,
            y: 10 + stain.height * 0.02 + oozeSlide * 0.12,
            width: width,
            height: height
        )
    }

    private func lobeRect(for lobe: GoblinSpitLobeSpec, in pool: CGRect) -> CGRect {
        CGRect(
            x: pool.midX + lobe.xOffset - lobe.width * 0.5,
            y: pool.minY + lobe.yOffset - lobe.height * 0.5,
            width: lobe.width,
            height: lobe.height
        )
    }

    private func dripRect(for drip: GoblinSpitDripSpec, in pool: CGRect) -> CGRect {
        let reveal = max(0.16, tailReveal)
        let effectiveLength = max(18, drip.length * reveal)
        return CGRect(
            x: pool.midX + drip.xOffset - drip.width * 0.5,
            y: pool.maxY - drip.width * 0.18 + oozeSlide * 0.08,
            width: drip.width,
            height: effectiveLength + drip.width * 0.98
        )
    }

    private func satelliteRect(for satellite: GoblinSpitSatelliteSpec, in pool: CGRect) -> CGRect {
        CGRect(
            x: pool.midX + satellite.xOffset - satellite.width * 0.5,
            y: pool.maxY + satellite.yOffset - satellite.height * 0.5,
            width: satellite.width,
            height: satellite.height
        )
    }

    private func seededScalar(_ salt: Int, range: ClosedRange<CGFloat>) -> CGFloat {
        let raw = abs(stain.seed &* 1103515245 &+ salt &* 12345)
        let unit = CGFloat(raw % 10_000) / 10_000
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

private struct GoblinSpitBlobShape: Shape {
    let topInset: CGFloat
    let leftInset: CGFloat
    let rightInset: CGFloat
    let bottomSag: CGFloat
    let asymmetry: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        let p0 = CGPoint(x: rect.minX + w * leftInset, y: rect.minY + h * 0.48)
        let p1 = CGPoint(x: rect.minX + w * (0.18 + asymmetry * 0.03), y: rect.minY + h * (topInset + 0.10))
        let p2 = CGPoint(x: rect.midX + w * asymmetry * 0.10, y: rect.minY + h * topInset)
        let p3 = CGPoint(x: rect.maxX - w * (0.18 - asymmetry * 0.02), y: rect.minY + h * (topInset + 0.12))
        let p4 = CGPoint(x: rect.maxX - w * rightInset, y: rect.minY + h * 0.50)
        let p5 = CGPoint(x: rect.maxX - w * 0.22, y: rect.minY + h * 0.84)
        let p6 = CGPoint(x: rect.midX + w * asymmetry * 0.06, y: rect.minY + h * bottomSag)
        let p7 = CGPoint(x: rect.minX + w * 0.18, y: rect.minY + h * 0.82)

        var path = Path()
        path.move(to: p0)
        path.addQuadCurve(to: p1, control: CGPoint(x: rect.minX + w * 0.03, y: rect.minY + h * 0.22))
        path.addQuadCurve(to: p2, control: CGPoint(x: rect.minX + w * 0.34, y: rect.minY - h * 0.02))
        path.addQuadCurve(to: p3, control: CGPoint(x: rect.midX + w * asymmetry * 0.10, y: rect.minY - h * 0.04))
        path.addQuadCurve(to: p4, control: CGPoint(x: rect.maxX - w * 0.03, y: rect.minY + h * 0.22))
        path.addQuadCurve(to: p5, control: CGPoint(x: rect.maxX + w * 0.03, y: rect.minY + h * 0.74))
        path.addQuadCurve(to: p6, control: CGPoint(x: rect.maxX - w * 0.18, y: rect.maxY + h * 0.04))
        path.addQuadCurve(to: p7, control: CGPoint(x: rect.midX + w * asymmetry * 0.12, y: rect.maxY + h * 0.06))
        path.addQuadCurve(to: p0, control: CGPoint(x: rect.minX - w * 0.02, y: rect.minY + h * 0.72))
        path.closeSubpath()
        return path
    }
}

private struct GoblinSpitDripShape: Shape {
    let sway: CGFloat
    let bulbInflation: CGFloat
    let neckTaper: CGFloat
    /// Сдвиг массы капли влево/вправо — нерегулярный силуэт.
    let bulbSkew: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let skew = min(max(bulbSkew, -1), 1)
        let centerX = rect.midX + sway * w * 0.16 + skew * w * 0.12
        let topHalf = w * (0.26 + 0.06 * abs(skew))
        let neckHalf = max(w * 0.07, w * 0.12 * neckTaper)
        let bulbWLeft = w * (0.62 + 0.26 * bulbInflation) * (1.0 - 0.12 * max(0, skew))
        let bulbWRight = w * (0.62 + 0.26 * bulbInflation) * (1.0 + 0.12 * min(0, skew))
        let bulbH = w * (0.58 + 0.34 * bulbInflation)
        let shoulderY = rect.minY + h * 0.16
        let neckY = rect.minY + h * 0.62
        let bulbCenterY = rect.maxY - bulbH * 0.54

        let topL = CGPoint(x: rect.midX - topHalf, y: rect.minY + h * 0.02)
        let shoulderL = CGPoint(x: rect.midX - topHalf * 0.76 + skew * w * 0.04, y: shoulderY)
        let neckL = CGPoint(x: centerX - neckHalf, y: neckY)
        let bulbL = CGPoint(x: centerX - bulbWLeft, y: bulbCenterY)
        let bulbB = CGPoint(x: centerX + sway * w * 0.1 + skew * w * 0.14, y: rect.maxY)
        let bulbR = CGPoint(x: centerX + bulbWRight, y: bulbCenterY)
        let neckR = CGPoint(x: centerX + neckHalf, y: neckY)
        let shoulderR = CGPoint(x: rect.midX + topHalf * 0.58 + skew * w * 0.06, y: shoulderY)
        let topR = CGPoint(x: rect.midX + topHalf * 0.7, y: rect.minY + h * 0.02)

        var path = Path()
        path.move(to: topL)
        path.addQuadCurve(
            to: shoulderL,
            control: CGPoint(x: rect.midX - topHalf * 1.04, y: rect.minY + h * 0.07)
        )
        path.addQuadCurve(
            to: neckL,
            control: CGPoint(x: centerX - neckHalf * 1.22 + sway * w * 0.06, y: rect.minY + h * 0.4)
        )
        path.addQuadCurve(
            to: bulbL,
            control: CGPoint(x: centerX - neckHalf * 1.28 + skew * w * 0.1, y: rect.minY + h * 0.84)
        )
        path.addQuadCurve(
            to: bulbB,
            control: CGPoint(x: centerX - bulbWLeft * 0.55 - abs(skew) * w * 0.08, y: rect.maxY - bulbH * 0.05)
        )
        path.addQuadCurve(
            to: bulbR,
            control: CGPoint(x: centerX + bulbWRight * 0.58 + abs(skew) * w * 0.06, y: rect.maxY - bulbH * 0.03)
        )
        path.addQuadCurve(
            to: neckR,
            control: CGPoint(x: centerX + neckHalf * 1.08 + sway * w * 0.06, y: rect.minY + h * 0.84)
        )
        path.addQuadCurve(
            to: shoulderR,
            control: CGPoint(x: centerX + neckHalf * 0.96, y: rect.minY + h * 0.4)
        )
        path.addQuadCurve(
            to: topR,
            control: CGPoint(x: rect.midX + topHalf * 0.92, y: rect.minY + h * 0.07)
        )
        path.closeSubpath()
        return path
    }
}

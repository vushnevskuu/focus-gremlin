import AppKit
import SwiftUI

// MARK: - Tunables (слюна на стекле: резкая маска, без крупного blur как «картинки»)

private enum GoblinSpitRenderParams {
    /// Меньше blur → острее силуэт, меньше «водяной кляксы».
    static let maskBlurRadius: CGFloat = 2.15
    static let maskAlphaThreshold: CGFloat = 0.56
    static let contactShadowBlur: CGFloat = 3.2
    static let contactShadowOpacity: Double = 0.22
    static let specularBlur: CGFloat = 0.45
    static let dissolveBlurMax: CGFloat = 3.8
    /// Вязкость анимации: больше response = медленнее ползёт.
    static let oozeSpringResponse: Double = 0.58
    static let oozeSpringDamping: Double = 0.91
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
    @ObservedObject var viewModel: CompanionViewModel

    var body: some View {
        let dim = spitLayoutDimensions()
        spitZStack(width: dim.width, height: dim.height)
            .frame(width: dim.width, height: dim.height, alignment: .topLeading)
            .background(Color.clear)
            .allowsHitTesting(false)
    }

    /// Размер видимой области экрана: из модели (после `updateSpitPanel`) или сразу из `NSScreen`, без `GeometryReader` (у хостинга он часто даёт неверный первый проход).
    private func spitLayoutDimensions() -> CGSize {
        let s = viewModel.spitPanelContentSize
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
            // Старые ниже, новые сверху — как наслоение капель, без перерисовки в одну мета-форму.
            ForEach(Array(viewModel.spitStains.enumerated()), id: \.element.id) { index, stain in
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

    /// Приглушённый биологический оттенок (не неон, не мятная желейка) — читается и на белом.
    private var slimeBody: Color {
        Color(red: 0.58, green: 0.62, blue: 0.44)
    }

    private var slimeThick: Color {
        Color(red: 0.34, green: 0.40, blue: 0.26)
    }

    private var slimeThin: Color {
        Color(red: 0.82, green: 0.86, blue: 0.74).opacity(0.42)
    }

    private var slimeEdgeDarken: Color {
        Color(red: 0.18, green: 0.22, blue: 0.14)
    }

    private var slimeContactShadow: Color {
        Color(white: 0.2)
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
            contactShadowView
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

    /// Тень у плоскости стекла: мягкая, низкая, без «летающего» пятна.
    private var contactShadowView: some View {
        Ellipse()
            .fill(slimeContactShadow.opacity(GoblinSpitRenderParams.contactShadowOpacity))
            .frame(width: stain.width * (0.72 + oozeSpread * 0.14), height: max(8, stain.height * 0.12))
            .blur(radius: GoblinSpitRenderParams.contactShadowBlur)
            .offset(y: stain.height * 0.26 + stain.tailLength * 0.04 + oozeSlide * 0.06)
    }

    /// Тело слюны: маска → толщина/альфа → узкие блики → лёгкий контраст по краю. Без крупного blur как основы формы.
    private var salivaMaterialView: some View {
        let mask = gooMaskView
        return ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            slimeThin,
                            slimeBody.opacity(0.78),
                            slimeThick.opacity(0.88),
                            slimeThick.opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RadialGradient(
                        colors: [
                            slimeThick.opacity(0.35),
                            slimeBody.opacity(0.12),
                            Color.clear
                        ],
                        center: .init(x: 0.44, y: 0.36),
                        startRadius: 2,
                        endRadius: stain.width * 0.55
                    )
                    .blendMode(.multiply)
                }
                .overlay {
                    RadialGradient(
                        colors: [
                            slimeEdgeDarken.opacity(0.45),
                            Color.clear
                        ],
                        center: .bottom,
                        startRadius: stain.width * 0.08,
                        endRadius: stain.width * 0.95
                    )
                    .blendMode(.multiply)
                }
                .mask(mask)

            thicknessHighlightLayer
                .mask(mask)

            specularHighlightLayer
                .mask(mask)

            glassClearcoatRim
                .mask(mask)
        }
        .frame(width: surfaceFrameWidth, height: surfaceFrameHeight)
    }

    /// Внутренняя «толще» в центре — тоньше по краю (без размытого облака).
    private var thicknessHighlightLayer: some View {
        ZStack {
            Ellipse()
                .fill(slimeThick.opacity(0.18))
                .frame(width: stain.width * 0.48, height: stain.height * 0.28)
                .offset(x: -stain.width * 0.04, y: -stain.height * 0.02)
            ForEach(dripSpecs, id: \.id) { drip in
                let reveal = max(0.16, tailReveal)
                let effectiveLength = max(18, drip.length * reveal)
                Capsule(style: .continuous)
                    .fill(slimeThick.opacity(drip.id == 0 ? 0.22 : 0.14))
                    .frame(width: max(3, drip.width * 0.22), height: effectiveLength * 0.55)
                    .offset(
                        x: drip.xOffset,
                        y: stain.height * 0.58 + effectiveLength * 0.26
                    )
            }
        }
        .blendMode(.multiply)
    }

    /// Узкие глянцевые полоски, не диффузное свечение.
    private var specularHighlightLayer: some View {
        ZStack {
            ForEach(dripSpecs, id: \.id) { drip in
                let reveal = max(0.16, tailReveal)
                let effectiveLength = max(18, drip.length * reveal)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(drip.id == 0 ? 0.42 : 0.28))
                    .frame(width: max(1.2, drip.width * 0.09), height: effectiveLength * 0.42)
                    .blur(radius: GoblinSpitRenderParams.specularBlur)
                    .offset(
                        x: drip.xOffset - drip.width * 0.12,
                        y: stain.height * 0.52 + effectiveLength * 0.24
                    )
                    .blendMode(.screen)
            }
            Ellipse()
                .fill(Color.white.opacity(0.28))
                .frame(width: stain.width * 0.22, height: stain.height * 0.06)
                .blur(radius: 0.9)
                .offset(
                    x: -stain.width * 0.08 + seededScalar(11, range: -4...6),
                    y: -stain.height * 0.08
                )
                .blendMode(.screen)
        }
    }

    /// Тонкий френель/обод — без широкого размытого ореола.
    private var glassClearcoatRim: some View {
        ZStack {
            Ellipse()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.38),
                            Color.white.opacity(0.12),
                            slimeThin.opacity(0.2),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
                .frame(width: stain.width * (1.04 + oozeSpread * 0.10), height: stain.height * (0.88 + oozeSpread * 0.06))
                .offset(y: -stain.height * 0.05)
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.04), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: max(4, stain.width * 0.08), height: stain.height * 0.45)
                .offset(x: -stain.width * 0.18, y: -stain.height * 0.02)
                .blur(radius: 0.55)
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
                            neckTaper: drip.neckTaper
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
        let oozeDuration = TimeInterval(seededScalar(52, range: 2.8...3.8))

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

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let centerX = rect.midX + sway * w * 0.16
        let topHalf = w * 0.28
        let neckHalf = max(w * 0.08, w * 0.13 * neckTaper)
        let bulbW = w * (0.72 + 0.22 * bulbInflation)
        let bulbH = w * (0.62 + 0.30 * bulbInflation)
        let shoulderY = rect.minY + h * 0.18
        let neckY = rect.minY + h * 0.64
        let bulbCenterY = rect.maxY - bulbH * 0.56

        let topL = CGPoint(x: rect.midX - topHalf, y: rect.minY + h * 0.02)
        let shoulderL = CGPoint(x: rect.midX - topHalf * 0.78, y: shoulderY)
        let neckL = CGPoint(x: centerX - neckHalf, y: neckY)
        let bulbL = CGPoint(x: centerX - bulbW * 0.5, y: bulbCenterY)
        let bulbB = CGPoint(x: centerX + sway * w * 0.08, y: rect.maxY)
        let bulbR = CGPoint(x: centerX + bulbW * 0.5, y: bulbCenterY)
        let neckR = CGPoint(x: centerX + neckHalf, y: neckY)
        let shoulderR = CGPoint(x: rect.midX + topHalf * 0.62, y: shoulderY)
        let topR = CGPoint(x: rect.midX + topHalf * 0.72, y: rect.minY + h * 0.02)

        var path = Path()
        path.move(to: topL)
        path.addQuadCurve(
            to: shoulderL,
            control: CGPoint(x: rect.midX - topHalf * 1.08, y: rect.minY + h * 0.08)
        )
        path.addQuadCurve(
            to: neckL,
            control: CGPoint(x: centerX - neckHalf * 1.26 + sway * w * 0.08, y: rect.minY + h * 0.42)
        )
        path.addQuadCurve(
            to: bulbL,
            control: CGPoint(x: centerX - neckHalf * 1.34 + sway * w * 0.08, y: rect.minY + h * 0.88)
        )
        path.addQuadCurve(to: bulbB, control: CGPoint(x: centerX - bulbW * 0.62, y: rect.maxY - bulbH * 0.04))
        path.addQuadCurve(to: bulbR, control: CGPoint(x: centerX + bulbW * 0.62, y: rect.maxY - bulbH * 0.02))
        path.addQuadCurve(
            to: neckR,
            control: CGPoint(x: centerX + neckHalf * 1.12 + sway * w * 0.08, y: rect.minY + h * 0.88)
        )
        path.addQuadCurve(
            to: shoulderR,
            control: CGPoint(x: centerX + neckHalf * 1.00, y: rect.minY + h * 0.42)
        )
        path.addQuadCurve(
            to: topR,
            control: CGPoint(x: rect.midX + topHalf * 0.96, y: rect.minY + h * 0.08)
        )
        path.closeSubpath()
        return path
    }
}

import Foundation
import MetalKit
import QuartzCore
import simd

@MainActor
final class SalivaMetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let commandQueue: MTLCommandQueue

    private var uniformHeader = SalivaUniformHeader(
        viewportSize: .zero,
        time: 0,
        stainCount: 0,
        flags: 0,
        refractionStrength: 1.22,
        specularIntensity: 0.48,
        fresnelPower: 3.2,
        thicknessContrast: 0.52,
        trailOpacity: 0.42,
        edgeIrregularity: 1.0,
        viscosityVisual: 0.34,
        strandWobble: 0.45,
        mergeSmooth: 0.55,
        padA: 0,
        padB: 0
    )

    private var stainBuffer: [StainBlobData] = Array(repeating: StainBlobData(
        center: .zero,
        halfAxes: .zero,
        rotation: 0,
        tailUV: 0,
        thicknessMul: 1,
        dissolve: 0,
        seed: 0,
        tailStretch: 0,
        micro0: .zero,
        micro1: .zero,
        micro2: .zero,
        padx: 0
    ), count: 8)

    private var startTime: CFTimeInterval = 0
    private weak var mtkView: MTKView?
    /// Вызывается в начале каждого `draw(in:)` (MainActor): обновить буферы пятен/растворения без лишних `draw()`.
    var beforeDraw: (() -> Void)?

    override init() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue()
        else {
            fatalError("Metal недоступен")
        }
        device = dev
        commandQueue = queue

        let lib = dev.makeDefaultLibrary()!
        let vd = MTLRenderPipelineDescriptor()
        vd.vertexFunction = lib.makeFunction(name: "saliva_vertex")
        vd.fragmentFunction = lib.makeFunction(name: "saliva_fragment")
        vd.rasterSampleCount = 1
        if let attachment = vd.colorAttachments[0] {
            attachment.pixelFormat = .bgra8Unorm
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.sourceAlphaBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        pipeline = try! dev.makeRenderPipelineState(descriptor: vd)
        super.init()
    }

    func attach(view: MTKView) {
        mtkView = view
        view.device = device
        view.delegate = self
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.enableSetNeedsDisplay = false
        // Ниже 30: меньше конкуренция с главным потоком (панель гоблина + композит). Размер drawable режем в `SpitMetalContainerView`.
        view.preferredFramesPerSecond = 22
        view.autoResizeDrawable = false
        if startTime == 0 {
            startTime = CACurrentMediaTime()
        }
        Self.configureTransparentMetalLayer(for: view)
    }

    /// Без этого `CAMetalLayer` часто остаётся opaque — альфа игнорируется, капель не видно.
    static func configureTransparentMetalLayer(for view: MTKView) {
        view.layer?.isOpaque = false
        if let metal = view.layer as? CAMetalLayer {
            metal.isOpaque = false
            metal.backgroundColor = CGColor(gray: 0, alpha: 0)
        }
    }

    func setPaused(_ paused: Bool) {
        mtkView?.isPaused = paused
        if !paused {
            mtkView?.draw()
        }
    }

    /// Один проход только с clear (прозрачный фон), без плевков.
    func clearToTransparent() {
        uniformHeader.stainCount = 0
        mtkView?.draw()
    }

    /// Записать uniform и буфер пятен; **не** вызывать `draw()` — кадр идёт от MTKView.
    func commitStainData(viewport: CGSize, stains: [StainBlobData], debugGridTint: Bool) {
        uniformHeader.viewportSize = SIMD2(Float(max(viewport.width, 1)), Float(max(viewport.height, 1)))
        uniformHeader.time = Float(CACurrentMediaTime() - startTime)
        uniformHeader.stainCount = UInt32(min(stains.count, 8))
        var f: UInt32 = 0
        if debugGridTint { f |= 1 }
        if ProcessInfo.processInfo.environment["FOCUSGREMLIN_SPIT_DEBUG_CHECKER"] == "1" {
            f |= 2
        }
        uniformHeader.flags = f
        for i in 0..<8 {
            stainBuffer[i] = i < stains.count ? stains[i] : StainBlobData(
                center: .zero,
                halfAxes: .zero,
                rotation: 0,
                tailUV: 0,
                thicknessMul: 0,
                dissolve: 1,
                seed: 0,
                tailStretch: 0,
                micro0: .zero,
                micro1: .zero,
                micro2: .zero,
                padx: 0
            )
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        beforeDraw?()
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        if uniformHeader.stainCount > 0 {
            enc.setRenderPipelineState(pipeline)
            var h = uniformHeader
            h.time = Float(CACurrentMediaTime() - startTime)
            enc.setFragmentBytes(&h, length: MemoryLayout<SalivaUniformHeader>.stride, index: 0)
            enc.setFragmentBytes(stainBuffer, length: MemoryLayout<StainBlobData>.stride * 8, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}

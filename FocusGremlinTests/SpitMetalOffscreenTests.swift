import Metal
import XCTest
import simd

@testable import FocusGremlin

/// Проверка без MTKView: шейдер реально пишет ненулевую альфу (иначе проблема не в композите панели).
final class SpitMetalOffscreenTests: XCTestCase {
    func testSalivaFragmentProducesNonZeroAlphaAtCenter() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal device недоступен")
            return
        }
        guard let library = device.makeDefaultLibrary() else {
            XCTFail("default.metallib не загрузился (хост FocusGremlin?)")
            return
        }
        guard let vs = library.makeFunction(name: "saliva_vertex"),
              let fs = library.makeFunction(name: "saliva_fragment")
        else {
            XCTFail("Функции saliva_vertex/saliva_fragment не найдены")
            return
        }

        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = vs
        pd.fragmentFunction = fs
        pd.colorAttachments[0].pixelFormat = .bgra8Unorm
        pd.colorAttachments[0].isBlendingEnabled = false
        let pipeline = try device.makeRenderPipelineState(descriptor: pd)

        let w = 128
        let h = 128
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: td) else {
            XCTFail("Не удалось создать текстуру")
            return
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let cmdQueue = device.makeCommandQueue(),
              let cb = cmdQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass)
        else {
            XCTFail("Command queue / buffer / encoder")
            return
        }

        var header = SalivaUniformHeader(
            viewportSize: SIMD2(Float(w), Float(h)),
            time: 0.5,
            stainCount: 1,
            flags: 0,
            refractionStrength: 1.05,
            specularIntensity: 0.38,
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
        var stains = [StainBlobData](repeating: StainBlobData(
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
        ), count: 8)
        stains[0] = StainBlobData(
            center: SIMD2(0.5, 0.5),
            halfAxes: SIMD2(0.14, 0.11),
            rotation: 0,
            tailUV: 0.35,
            thicknessMul: 1,
            dissolve: 0,
            seed: 3.14,
            tailStretch: 0.25,
            micro0: SIMD2(0.02, -0.015),
            micro1: SIMD2(-0.018, 0.01),
            micro2: SIMD2(0.01, 0.02),
            padx: 0
        )

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&header, length: MemoryLayout<SalivaUniformHeader>.stride, index: 0)
        enc.setFragmentBytes(&stains, length: MemoryLayout<StainBlobData>.stride * 8, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        var px = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &px,
            bytesPerRow: w * 4,
            from: MTLRegionMake2D(w / 2, h / 2, 1, 1),
            mipmapLevel: 0
        )
        let a = px[3]
        XCTAssertGreaterThan(a, 15, "Центр кадра должен иметь заметную альфу, получили BGRA=\(px)")
    }

    /// Без пятен не должно быть «шахматки» на весь кадр (регресс полуэкранной альфы от fresnel).
    func testSalivaFragmentFullyTransparentWhenNoStains() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary(),
              let vs = library.makeFunction(name: "saliva_vertex"),
              let fs = library.makeFunction(name: "saliva_fragment"),
              let cmdQueue = device.makeCommandQueue()
        else {
            XCTFail("Metal init")
            return
        }
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = vs
        pd.fragmentFunction = fs
        pd.colorAttachments[0].pixelFormat = .bgra8Unorm
        pd.colorAttachments[0].isBlendingEnabled = false
        let pipeline = try device.makeRenderPipelineState(descriptor: pd)

        let w = 64
        let h = 64
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: td))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.2, green: 0.3, blue: 0.25, alpha: 1)

        let cb = try XCTUnwrap(cmdQueue.makeCommandBuffer())
        let enc = try XCTUnwrap(cb.makeRenderCommandEncoder(descriptor: pass))

        var header = SalivaUniformHeader(
            viewportSize: SIMD2(Float(w), Float(h)),
            time: 0.5,
            stainCount: 0,
            flags: 0,
            refractionStrength: 1.05,
            specularIntensity: 0.38,
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
        let stains = [StainBlobData](repeating: StainBlobData(
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
        ), count: 8)

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&header, length: MemoryLayout<SalivaUniformHeader>.stride, index: 0)
        enc.setFragmentBytes(stains, length: MemoryLayout<StainBlobData>.stride * 8, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        var px = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &px,
            bytesPerRow: w * 4,
            from: MTLRegionMake2D(w / 2, h / 2, 1, 1),
            mipmapLevel: 0
        )
        XCTAssertLessThan(
            Int(px[3]),
            8,
            "Без пятен центр кадра должен остаться от clear (альфа из шейдера ~0), BGRA=\(px)"
        )
    }

    /// Регресс: углы кадра прозрачны, если пятно только в центре (нет полноэкранного пола от smoothMax).
    func testSalivaFragmentTransparentAtCornerWhenStainOnlyAtCenter() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary(),
              let vs = library.makeFunction(name: "saliva_vertex"),
              let fs = library.makeFunction(name: "saliva_fragment"),
              let cmdQueue = device.makeCommandQueue()
        else {
            XCTFail("Metal init")
            return
        }
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = vs
        pd.fragmentFunction = fs
        pd.colorAttachments[0].pixelFormat = .bgra8Unorm
        pd.colorAttachments[0].isBlendingEnabled = false
        let pipeline = try device.makeRenderPipelineState(descriptor: pd)

        let w = 256
        let h = 256
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: td))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        let cb = try XCTUnwrap(cmdQueue.makeCommandBuffer())
        let enc = try XCTUnwrap(cb.makeRenderCommandEncoder(descriptor: pass))

        var header = SalivaUniformHeader(
            viewportSize: SIMD2(Float(w), Float(h)),
            time: 0.5,
            stainCount: 1,
            flags: 0,
            refractionStrength: 1.05,
            specularIntensity: 0.38,
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
        var stains = [StainBlobData](repeating: StainBlobData(
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
        ), count: 8)
        stains[0] = StainBlobData(
            center: SIMD2(0.5, 0.5),
            halfAxes: SIMD2(0.12, 0.1),
            rotation: 0,
            tailUV: 0.32,
            thicknessMul: 1,
            dissolve: 0,
            seed: 2.71,
            tailStretch: 0.2,
            micro0: .zero,
            micro1: .zero,
            micro2: .zero,
            padx: 0
        )

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&header, length: MemoryLayout<SalivaUniformHeader>.stride, index: 0)
        enc.setFragmentBytes(&stains, length: MemoryLayout<StainBlobData>.stride * 8, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        var px = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &px,
            bytesPerRow: w * 4,
            from: MTLRegionMake2D(2, 2, 1, 1),
            mipmapLevel: 0
        )
        XCTAssertLessThan(
            Int(px[3]),
            10,
            "Угол (2,2) должен быть прозрачным при пятне в центре, BGRA=\(px)"
        )
    }

    /// При длинном хвосте нижняя «капля» тянет максимум альфы ниже центра (регресс острых диагональных эллипсов без массы внизу).
    func testSalivaTailShiftsAlphaCentroidDownward() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary(),
              let vs = library.makeFunction(name: "saliva_vertex"),
              let fs = library.makeFunction(name: "saliva_fragment"),
              let cmdQueue = device.makeCommandQueue()
        else {
            XCTFail("Metal init")
            return
        }
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = vs
        pd.fragmentFunction = fs
        pd.colorAttachments[0].pixelFormat = .bgra8Unorm
        pd.colorAttachments[0].isBlendingEnabled = false
        let pipeline = try device.makeRenderPipelineState(descriptor: pd)

        let w = 256
        let h = 256
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: td))

        func centroidAlphaColumn(tailUV: Float, tailStretch: Float, seed: Float) throws -> Float {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

            let cb = try XCTUnwrap(cmdQueue.makeCommandBuffer())
            let enc = try XCTUnwrap(cb.makeRenderCommandEncoder(descriptor: pass))

            var header = SalivaUniformHeader(
                viewportSize: SIMD2(Float(w), Float(h)),
                time: 0.5,
                stainCount: 1,
                flags: 0,
                refractionStrength: 1.05,
                specularIntensity: 0.38,
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
            var stains = [StainBlobData](repeating: StainBlobData(
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
            ), count: 8)
            stains[0] = StainBlobData(
                center: SIMD2(0.5, 0.5),
                halfAxes: SIMD2(0.13, 0.1),
                rotation: 0,
                tailUV: tailUV,
                thicknessMul: 1,
                dissolve: 0,
                seed: seed,
                tailStretch: tailStretch,
                micro0: .zero,
                micro1: .zero,
                micro2: .zero,
                padx: 0
            )

            enc.setRenderPipelineState(pipeline)
            enc.setFragmentBytes(&header, length: MemoryLayout<SalivaUniformHeader>.stride, index: 0)
            enc.setFragmentBytes(&stains, length: MemoryLayout<StainBlobData>.stride * 8, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()

            let x = w / 2
            var sumA: Float = 0
            var sumYA: Float = 0
            var row = [UInt8](repeating: 0, count: 4)
            for y in 0 ..< h {
                texture.getBytes(
                    &row,
                    bytesPerRow: w * 4,
                    from: MTLRegionMake2D(x, y, 1, 1),
                    mipmapLevel: 0
                )
                let a = Float(row[3])
                sumA += a
                sumYA += Float(y) * a
            }
            XCTAssertGreaterThan(sumA, 200, "Должна быть заметная альфа по колонке")
            return sumYA / sumA
        }

        let shortCentroid = try centroidAlphaColumn(tailUV: 0.12, tailStretch: 0.04, seed: 1.41)
        let longCentroid = try centroidAlphaColumn(tailUV: 0.42, tailStretch: 0.36, seed: 1.41)
        XCTAssertGreaterThan(
            longCentroid,
            shortCentroid + 4,
            "Длинный хвост должен сместить центр альфы вниз: short=\(shortCentroid) long=\(longCentroid)"
        )
    }
}

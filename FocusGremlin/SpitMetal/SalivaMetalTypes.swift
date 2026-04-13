import simd

/// Совпадает по полям и выравнивании с `SalivaUniformHeader` в `SalivaMetalShader.metal`.
struct SalivaUniformHeader {
    var viewportSize: SIMD2<Float>
    var time: Float
    var stainCount: UInt32
    var flags: UInt32
    var refractionStrength: Float
    var specularIntensity: Float
    var fresnelPower: Float
    var thicknessContrast: Float
    var trailOpacity: Float
    var edgeIrregularity: Float
    var viscosityVisual: Float
    var strandWobble: Float
    var mergeSmooth: Float
    var padA: Float
    var padB: Float
}

/// Совпадает с `StainBlobData` в `SalivaMetalShader.metal` (64 байта на элемент).
struct StainBlobData {
    var center: SIMD2<Float>
    var halfAxes: SIMD2<Float>
    var rotation: Float
    var tailUV: Float
    var thicknessMul: Float
    var dissolve: Float
    var seed: Float
    var tailStretch: Float
    var micro0: SIMD2<Float>
    var micro1: SIMD2<Float>
    var micro2: SIMD2<Float>
    var padx: Float
}

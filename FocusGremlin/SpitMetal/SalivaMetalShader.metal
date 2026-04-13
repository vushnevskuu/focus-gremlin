#include <metal_stdlib>
using namespace metal;

struct SalivaUniformHeader {
    float2 viewportSize;
    float time;
    uint stainCount;
    uint flags;
    float refractionStrength;
    float specularIntensity;
    float fresnelPower;
    float thicknessContrast;
    float trailOpacity;
    float edgeIrregularity;
    float viscosityVisual;
    float strandWobble;
    float mergeSmooth;
    float padA;
    float padB;
};

struct StainBlobData {
    float2 center;
    float2 halfAxes;
    float rotation;
    float tailUV;
    float thicknessMul;
    float dissolve;
    float seed;
    float tailStretch;
    float2 micro0;
    float2 micro1;
    float2 micro2;
    float padx;
};

struct RasterOut {
    float4 position [[position]];
    float2 uv;
};

vertex RasterOut saliva_vertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    float2 uv[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };
    RasterOut o;
    o.position = float4(pos[vid], 0.0, 1.0);
    o.uv = uv[vid];
    return o;
}

static float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

static float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

static float hash21(float2 p) {
    return hash22(p).x;
}

static float2 rotate2(float2 p, float c, float s) {
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

static float smoothMax(float a, float b, float k) {
    if (k < 1e-4) return max(a, b);
    return log(exp(k * a) + exp(k * b)) / k;
}

/// Объединение положительных «толщин»: log-sum-exp даёт пол log(2)/k при a=b=0 — это и было полноэкранной слизью.
/// Если одна ветка ~0 — берём другую; если обе ~0 — 0; иначе — гладкое слияние там, где капли реально пересекаются.
static float mergeThickPositive(float a, float b, float k) {
    const float eps = 1e-5;
    if (a < eps && b < eps) return 0.0;
    if (a < eps) return b;
    if (b < eps) return a;
    return smoothMax(a, b, k);
}

/// Статичный по времени «лоб»: только hash по углу — без вращения и без sin(t).
static float staticIrregularLobe(float2 p, float2 lobeCenter, float rx, float ry, float rotAmt, float seed, float edgeN) {
    float2 q = p - lobeCenter;
    float c = cos(rotAmt);
    float s = sin(rotAmt);
    q = rotate2(q, c, s);
    float ang = atan2(q.y, q.x);
    float rim = (hash21(float2(seed * 3.17, ang * (3.2 + hash11(seed * 1.9) * 2.0)))) - 0.5;
    rim *= 0.055 * edgeN;
    float rr = length(float2(q.x / max(rx, 1e-4), q.y / max(ry, 1e-4))) + rim;
    // Низкочастотная вариация — без «зёрна» и полос от hash(q*11).
    float lump = 0.94 + 0.06 * (hash21(q * 2.2 + seed * 0.41) - 0.5);
    return saturate((1.0 - smoothstep(0.34, 0.96, rr)) * lump);
}

static float softMicro(float2 uv, float2 center, float rad) {
    float2 d = uv - center;
    float r = length(d) / max(rad, 1e-4);
    // Мягкая бусина: широкий переход, без тонкого кольца (нет «звезды» от нормалей).
    float core = 1.0 - smoothstep(0.0, 0.72, r);
    float edge = 1.0 - smoothstep(0.58, 1.0, r);
    return saturate(core * 0.38 + edge * 0.1);
}

/// Толщина: метаболы + хвост от CPU tailStretch, микрокапли из симуляции. Нет UV-дрейфа и «вихря» по времени.
static float stainThicknessField(float2 uv, constant StainBlobData& S, float edgeNoise, float mergeK) {
    float2 centerEff = mix(S.center, float2(0.5, 0.5), 0.06);
    float co = cos(S.rotation);
    float si = sin(S.rotation);
    float2 d = uv - centerEff;
    float2 pr = rotate2(d, co, si);

    float ax = max(S.halfAxes.x, 1e-4);
    float ay = max(S.halfAxes.y, 1e-4);
    float life = 1.0 - saturate(S.dissolve);
    float ts = saturate(S.tailStretch);

    float2 h0 = hash22(float2(S.seed * 1.9, 0.21));
    float2 h1 = hash22(float2(S.seed * 3.7, 1.11));
    float2 h2 = hash22(float2(S.seed * 5.3, 2.41));

    float mk = mergeK * 0.5;
    float body = 0.0;

    float2 off0 = float2((h0.x - 0.52) * ax * 0.58, (h0.y - 0.48) * ay * 0.46);
    body = mergeThickPositive(body, staticIrregularLobe(pr, off0, ax * 0.9, ay * 0.78, (h0.x - 0.5) * 1.1, S.seed + 0.11, edgeNoise), mk);

    float2 off1 = float2((h1.x - 0.5) * ax * 0.94, (h1.y - 0.55) * ay * 0.88 - ay * 0.12);
    body = mergeThickPositive(body, staticIrregularLobe(pr, off1, ax * 0.6, ay * 0.56, -(h1.y) * 0.9, S.seed + 1.73, edgeNoise), mk);

    float2 off2 = float2((h2.x - 0.48) * ax * 0.44, (h2.y - 0.62) * ay * 0.4);
    body = mergeThickPositive(body, staticIrregularLobe(pr, off2, ax * 0.52, ay * 0.48, (h2.x - h2.y) * 0.62, S.seed + 3.21, edgeNoise), mk);

    float2 bulbC = float2((h1.x - 0.5) * ax * 0.2, ay * (0.12 + ts * 0.18));
    float bulb = staticIrregularLobe(pr, bulbC, ax * 0.46, ay * 0.4, hash11(S.seed * 2.0) * 0.4, S.seed + 9.05, edgeNoise);
    body = mergeThickPositive(body, bulb, mk * 0.55);

    float pocketN = hash21(pr * 2.8 + float2(S.seed * 0.31, 0.0));
    body *= 0.93 + 0.07 * pocketN * smoothstep(0.2, 0.9, body);

    // Хвост: не симметричный эллипс (лист/миндаль). yN<0 — к основной массе, yN>0 — вниз, тяжёлая капля.
    float tailPh = S.tailUV * (0.7 + ts * 0.15);
    float neckPinch = mix(1.05, 0.58, ts);
    float wBase = ax * (0.095 + 0.035 * hash11(S.seed * 4.2));
    float wJag = (hash21(float2(S.seed * 2.3, pr.y * 2.8 + S.seed * 0.17)) - 0.5) * ax * 0.018 * edgeNoise;
    float2 tailOrg = pr - float2(0.0, tailPh);
    float ty = ay * (0.48 + S.tailUV * 0.5) * (1.0 + ts * 0.1);
    float tyNeck = ty * 0.74;
    float tyBulb = ty * 0.58;
    float yN = tailOrg.y;

    float neckW = wBase * neckPinch * mix(0.24, 0.52, smoothstep(-tyNeck * 1.08, -tyNeck * 0.08, yN));
    neckW *= mix(0.88, 1.05, smoothstep(0.0, tyNeck * 0.5, yN));
    float xEdge = abs(tailOrg.x) / max(neckW + wJag, 1e-4);
    float neckTop = smoothstep(-tyNeck * 1.18, -tyNeck * 0.22, yN);
    float neckBot = 1.0 - smoothstep(tyNeck * 0.08, tyNeck * 0.58, yN);
    float neckLen = saturate(neckTop * neckBot);
    float neck = (1.0 - smoothstep(0.28, 0.94, xEdge)) * neckLen * (0.38 + 0.22 * (1.0 - xEdge));

    // Нижняя капля: масса внизу (круглый «шарик»), не симметричный эллипс/миндаль.
    float2 hBulb = hash22(float2(S.seed * 8.2, 31.0));
    float bx = (hBulb.x - 0.5) * neckW * 0.42;
    float lean = (hash21(float2(S.seed * 1.91, 44.0)) - 0.5) * 0.11 * edgeNoise;
    float coB = cos(lean);
    float siB = sin(lean);
    float2 tailRot = rotate2(tailOrg - float2(bx, 0.0), coB, -siB);

    float yNeckJoin = -tyNeck * 0.12;
    float yBulbCenter = tyBulb * (0.58 + 0.06 * hBulb.y) + wJag * 0.25;
    float2 botC = float2(bx * 0.35 + wJag * 0.4, yBulbCenter);

    float2 rel = tailRot - botC;
    float yNorm = rel.y / max(tyBulb * 0.62, 1e-4);
    float widen = mix(0.38, 1.12, smoothstep(-0.55, 0.92, yNorm + 0.08));
    widen *= mix(0.92, 1.08, smoothstep(0.35, 1.05, yNorm));
    float rxEff = neckW * (0.95 + 0.22 * hash11(S.seed * 5.03)) * widen;
    float ryEff = tyBulb * (0.48 + 0.12 * hash11(S.seed * 5.71));

    float angB = atan2(rel.y, rel.x + 1e-4);
    float rimB = (hash21(float2(S.seed * 1.13, angB * 2.0)) - 0.5) * 0.045 * edgeNoise;
    float rimB2 = (hash21(float2(S.seed * 2.07, angB * 1.2 + rel.y * 2.5)) - 0.5) * 0.022 * edgeNoise;

    float horiz = abs(rel.x) / max(rxEff + rimB2, 1e-4);
    float vertU = max(-rel.y / max(tyNeck * 0.55, 1e-4), 0.0);
    float vertD = max(rel.y / max(ryEff, 1e-4), 0.0);
    float cap = length(float2(max(0.0, horiz - 0.12), vertD)) + rimB * 0.65;
    float upperPinch = vertU * (0.95 + 0.35 * smoothstep(0.0, 0.55, horiz));
    float rAsym = max(cap * 0.92, upperPinch);
    float bulbCore = 1.0 - smoothstep(0.38, 0.99, rAsym);

    float2 tipC = tailRot - float2(bx * 0.2 + (hBulb.x - 0.5) * neckW * 0.25, yBulbCenter + ryEff * 0.72);
    float rTip = length(tipC / max(float2(rxEff * 0.92, ryEff * 0.48), float2(1e-4)));
    float tipBlob = (1.0 - smoothstep(0.28, 0.94, rTip + rimB * 0.4)) * 0.95;

    float bulbDrop = mergeThickPositive(bulbCore * 0.82, tipBlob * 0.88, mergeK * 0.55);
    bulbDrop *= smoothstep(yNeckJoin - tyNeck * 0.08, yBulbCenter * 0.35, tailRot.y);
    bulbDrop *= (0.5 + 0.42 * saturate(bulbDrop));

    float tail = mergeThickPositive(neck, bulbDrop, mergeK * 0.28);

    float2 hk = hash22(float2(S.seed * 2.47, 17.0));
    float2 finger = pr - float2((hk.x - 0.5) * ax * 1.22, (hk.y - 0.68) * ay * 0.92 - ay * 0.1);
    float rf = length(finger / max(float2(ax * 0.16, ay * 0.15), float2(1e-4)));
    float rimF = (hash21(float2(S.seed, atan2(finger.y, finger.x) * 2.2)) - 0.5) * 0.03 * edgeNoise;
    float fil = (1.0 - smoothstep(0.48, 1.02, rf + rimF)) * 0.28;

    float2 wMicro0 = S.center + S.micro0;
    float2 wMicro1 = S.center + S.micro1;
    float2 wMicro2 = S.center + S.micro2;
    float rMicro = (0.032 + hash11(S.seed * 6.1) * 0.018) * max(ax, ay) * 2.35;
    float micro = softMicro(uv, wMicro0, rMicro * 1.05);
    micro = mergeThickPositive(micro, softMicro(uv, wMicro1, rMicro * 1.0), mergeK * 0.55);
    micro = mergeThickPositive(micro, softMicro(uv, wMicro2, rMicro * 0.98), mergeK * 0.55);

    float m = body;
    m = mergeThickPositive(m, tail, mergeK * 0.34);
    m = mergeThickPositive(m, fil, mergeK * 0.4);
    m = mergeThickPositive(m, micro, mergeK * 0.48);

    float2 ph = pr + float2((h1.x - 0.5) * ax * 0.08, (h1.y - 0.5) * ay * 0.06);
    float rh = length(float2(ph.x / max(ax * 1.42, 1e-4), ph.y / max(ay * 1.38, 1e-4)));
    float halo = (1.0 - smoothstep(0.68, 0.98, rh)) * 0.016 * (1.0 - ts * 0.4);
    m = mergeThickPositive(m, halo, mergeK * 0.14);

    return m * S.thicknessMul * life;
}

/// Прокси под преломление: гладкий, без hash-муара и без ВЧ, которые «ползут» при сдвиге UV.
/// flags: bit0 — лёгкий зеленоватый оттенок (настройки); bit2 — только QA: искусственная шахматка.
static float3 refractionSceneProxy(float2 uv, uint flags) {
    if ((flags & 2u) != 0u) {
        float2 g = floor(uv * 28.0);
        float ch = fmod(g.x + g.y, 2.0);
        float3 dbg = mix(float3(0.07, 0.09, 0.08), float3(0.52, 0.55, 0.50), ch);
        if ((flags & 1u) != 0u) {
            dbg = mix(dbg, float3(0.22, 0.48, 0.26), 0.12);
        }
        return dbg;
    }

    float2 p = uv - 0.5;
    float L = 0.5 + p.x * 0.018 + p.y * 0.014 + (p.x * p.x - p.y * p.y) * 0.008;
    float3 col = float3(saturate(L));
    if ((flags & 1u) != 0u) {
        col = mix(col, float3(0.22, 0.48, 0.26), 0.045);
    }
    return col;
}

static float combinedThickness(
    float2 uv,
    float mergeK,
    float epsN,
    constant SalivaUniformHeader& H,
    constant StainBlobData* stains,
    uint n
) {
    float thickness = 0.0;
    for (uint i = 0; i < n; i++) {
        constant StainBlobData& S = stains[i];
        float c0 = stainThicknessField(uv, S, epsN, mergeK);
        thickness = mergeThickPositive(thickness, c0, mergeK * 0.35);
    }
    return thickness;
}

fragment float4 saliva_fragment(
    RasterOut in [[stage_in]],
    constant SalivaUniformHeader& H [[buffer(0)]],
    constant StainBlobData* stains [[buffer(1)]]
) {
    float2 uv = in.uv;

    float mergeK = 6.0 + H.mergeSmooth * 10.0;
    uint n = min(H.stainCount, 8u);

    float thickness = combinedThickness(uv, mergeK, H.edgeIrregularity, H, stains, n);
    float coverageEarly = smoothstep(0.0015f, 0.034f, thickness);
    if (coverageEarly <= 0.0f) {
        return float4(0.0f);
    }

    // Один вызов combinedThickness на пиксель: поле уже низкочастотное; dfdx/dfdy дают стабильный градиент без4× стоимости.
    float dudx = max(abs(dfdx(uv.x)), 1e-5);
    float dvdy = max(abs(dfdy(uv.y)), 1e-5);
    float2 grad = float2(dfdx(thickness) / dudx, dfdy(thickness) / dvdy);
    float gnRaw = length(grad);
    grad /= max(1.0, gnRaw * 0.62);
    float gn = length(grad);

    float T = pow(saturate(thickness), 0.62 + H.thicknessContrast * 0.32);
    float coverage = coverageEarly;

    float2 distort = -grad * H.refractionStrength * T * 0.034;
    float maxD = 0.0065;
    float dl = length(distort);
    if (dl > maxD) {
        distort *= maxD / dl;
    }
    float2 ruv = saturate(uv + distort);

    float3 bg = refractionSceneProxy(ruv, H.flags);

    // Лайм как в UI (CompanionBubble lineGreen), без «белой кляксы»: тело зелёное, блик — светло-зелёный.
    float3 slimeBody = float3(0.14, 0.78, 0.36);
    float3 slimeDeep = float3(0.06, 0.48, 0.24);
    float3 slimeHi = float3(0.52, 0.96, 0.62);
    float bodyMix = saturate(0.26 + T * 0.58);
    float3 baseGreen = mix(slimeDeep, slimeBody, bodyMix);
    float3 tinted = mix(bg, baseGreen, saturate(T * 0.62 + 0.1));

    float fres = pow(saturate(1.0 - gn * 0.28 - T * 0.28), H.fresnelPower);
    float3 fresCol = mix(tinted, slimeHi, fres * 0.34);

    float2 h = normalize(float2(0.35, 0.71));
    float spec = pow(saturate(dot(normalize(float3(-grad * 1.35, 1.0)), float3(h, 1.0) * 0.707)), 22.0);
    float3 specCol = float3(0.78, 0.98, 0.86) * spec * H.specularIntensity;

    float trail = saturate(T * H.trailOpacity * (0.32 + gn * 0.18));
    float3 outRgb = fresCol + specCol + float3(0.05, 0.14, 0.08) * trail;

    float alpha = saturate(T * 0.94 + fres * 0.14 + spec * 0.38);
    alpha *= coverage;
    return float4(outRgb, alpha);
}

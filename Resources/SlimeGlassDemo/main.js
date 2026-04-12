/**
 * SCREEN-SPACE SLIME ON GLASS (lens plane = monitor)
 *
 * BEFORE (failed): Pastel gradients + soft masks + fake drop shadows read as floating
 * stickers; white/flat BG hid refraction; blur/silhouette stood in for material.
 *
 * AFTER: Thickness field T on the plane → normals → Snell-style UV shift ∝ T;
 * Fresnel + sharp spec on the surface; Beer-ish absorption; residue RT for wet trails.
 * No floor shadows, no “object in front of glass” parallax — everything is glued to uv plane.
 *
 * Sections:
 * (a) PHYSICS — class SlimeBlob + mergeBlobs + applyStrandForces + integrate (viscosity, adhesion, gravity)
 * (b) OPTICAL — slimeFragment: thickness, ∇T normals, refraction, spec, Fresnel, tint
 * (c) RESIDUE — residueFragment: decay + vertical smear + thin-film max with current T
 */
import * as THREE from "three";
import { GUI } from "three/addons/libs/lil-gui.module.min.js";

const MAX_BLOBS = 10;

const bgVert = `#version 300 es
in vec3 position;
in vec2 uv;
out vec2 vUv;
void main(){ vUv=uv; gl_Position=vec4(position.xy,0.0,1.0); }
`;

// High-contrast debug plate so refraction reads immediately (not empty white).
const bgFrag = `#version 300 es
precision highp float;
in vec2 vUv;
out vec4 fragColor;
uniform float uTime;
float h(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void main(){
  vec2 uv=vUv;
  float ch = mod(floor(uv.x*32.0)+floor(uv.y*24.0), 2.0);
  vec3 black = vec3(0.02,0.02,0.03);
  vec3 white = vec3(0.94,0.94,0.92);
  vec3 c = mix(black, white, ch);
  float grid = max(
    smoothstep(0.48,0.5,abs(fract(uv.x*64.0)-0.5)),
    smoothstep(0.48,0.5,abs(fract(uv.y*48.0)-0.5))
  );
  c = mix(c, vec3(0.15,0.15,0.18), grid*0.85);
  float bar = step(0.72, abs(uv.x-0.5)) * step(0.35, uv.y) * step(uv.y, 0.65);
  c = mix(c, vec3(0.9,0.25,0.2), bar);
  float txt = step(0.55, sin(uv.x*120.0+uTime*0.5)) * step(0.4, sin(uv.y*90.0));
  c = mix(c, vec3(0.05,0.06,0.1), txt*0.6);
  c += 0.07 * h(uv*200.0);
  fragColor = vec4(c, 1.0);
}
`;

const slimeVert = bgVert;

const slimeFrag = `#version 300 es
precision highp float;
in vec2 vUv;
out vec4 fragColor;

uniform sampler2D uBg;
uniform sampler2D uResidue;
uniform vec2 uRes;
uniform float uTime;

uniform int uN;
uniform vec2 uP[${MAX_BLOBS}];
uniform float uR[${MAX_BLOBS}];
uniform float uAy[${MAX_BLOBS}];

uniform float uEdgeNoise;
uniform float uThickContrast;
uniform float uRefraction;
uniform float uSpecI;
uniform float uFreI;
uniform float uFrePow;
uniform float uTintStr;
uniform float uChroma;
uniform float uTrailOp;

float tri(in float x){ return abs(fract(x)-0.5); }
float fbm2(vec2 p){
  float v=0.0,a=0.5;
  mat2 m=mat2(1.6,1.2,-1.2,1.6);
  for(int i=0;i<4;i++){ v+=a*tri(p.x)+a*tri(p.y); p=m*p; a*=0.5; }
  return v;
}
vec2 warp(vec2 uv){
  vec2 q = uv * vec2(24.0, 31.0) + uTime * 0.03;
  return uv + uEdgeNoise * (fbm2(q)-0.4) * 0.018;
}

float kernel(vec2 d, float r, float ay){
  d.y *= ay;
  float s = dot(d,d) + 1e-8;
  return (r*r) / s;
}

float thicknessField(vec2 uv){
  float t = 0.0;
  for(int i=0;i<${MAX_BLOBS};i++){
    if(i>=uN) break;
    vec2 d = uv - uP[i];
    t += kernel(d, uR[i], uAy[i]);
  }
  return t;
}

float T_at(vec2 uv){
  return thicknessField(warp(uv));
}

void main(){
  vec2 uv = vUv;
  float raw = T_at(uv);

  // Optical thickness: steep ramp = sharp wet boundary, not airbrushed blob
  float tLo = 0.85;
  float tHi = 1.45;
  float shell = smoothstep(tLo, tLo + 0.08, raw);
  float core  = smoothstep(tLo + 0.12, tHi, raw);
  float T = mix(shell, core, uThickContrast) * smoothstep(0.0, 2.8, raw);
  T = clamp(T * 1.15, 0.0, 1.0);

  float e = 1.1 / max(uRes.x, uRes.y);
  float dTx = T_at(uv+vec2(e,0.0)) - T_at(uv-vec2(e,0.0));
  float dTy = T_at(uv+vec2(0.0,e)) - T_at(uv-vec2(0.0,e));
  vec3 N = normalize(vec3(-dTx * 25.0, -dTy * 25.0, 1.0));
  vec3 V = vec3(0.0, 0.0, 1.0);
  float NV = clamp(dot(N,V), 0.0, 1.0);

  float disp = uRefraction * pow(T, 1.35);
  vec2 off = N.xy * disp;
  vec2 ruv = uv + off;
  vec3 bR = texture(uBg, ruv + vec2(uChroma * T, 0.0)).rgb;
  vec3 bG = texture(uBg, ruv).rgb;
  vec3 bB = texture(uBg, ruv - vec2(uChroma * T, 0.0)).rgb;
  vec3 refr = vec3(bR.r, bG.g, bB.b);

  vec3 L = normalize(vec3(0.2, 0.75, 0.55));
  vec3 H = normalize(L + V);
  float NH = max(dot(N,H), 0.0);
  float spec = pow(NH, 280.0) * uSpecI * step(0.02, T);
  float fres = uFreI * pow(1.0 - NV, uFrePow);

  vec3 mucus = vec3(0.55, 0.62, 0.28);
  float absorb = 1.0 - exp(-T * 2.4);
  vec3 base = mix(refr, refr * mucus, absorb * uTintStr);

  vec3 lit = base + spec * vec3(1.0, 0.97, 0.93);
  lit = mix(lit, vec3(1.0, 0.99, 0.96), fres * 0.55 * shell);

  float res = texture(uResidue, uv).r * uTrailOp;
  float cover = max(T, res);
  float alpha = clamp(cover * 0.98 + fres * 0.1 * shell, 0.0, 1.0);

  vec3 bg0 = texture(uBg, uv).rgb;
  fragColor = vec4(mix(bg0, lit, alpha), 1.0);
}
`;

const resVert = bgVert;
const resFrag = `#version 300 es
precision highp float;
in vec2 vUv;
out vec4 fragColor;
uniform sampler2D uPrev;
uniform vec2 uRes;
uniform float uDecay;
uniform float uGrow;
uniform int uN;
uniform vec2 uP[${MAX_BLOBS}];
uniform float uR[${MAX_BLOBS}];
uniform float uAy[${MAX_BLOBS}];
uniform float uEdgeNoise;
uniform float uTime;

float tri(in float x){ return abs(fract(x)-0.5); }
float fbm2(vec2 p){
  float v=0.0,a=0.5;
  mat2 m=mat2(1.6,1.2,-1.2,1.6);
  for(int i=0;i<3;i++){ v+=a*tri(p.x)+a*tri(p.y); p=m*p; a*=0.5; }
  return v;
}
vec2 warp(vec2 uv){
  return uv + uEdgeNoise * (fbm2(uv*22.0+uTime*0.02)-0.4) * 0.018;
}
float kernel(vec2 d, float r, float ay){ d.y*=ay; return (r*r)/(dot(d,d)+1e-8); }
float Tthin(vec2 uv){
  float t=0.0;
  for(int i=0;i<${MAX_BLOBS};i++){
    if(i>=uN) break;
    vec2 d = warp(uv)-uP[i];
    t += kernel(d, uR[i], uAy[i]);
  }
  return t;
}
void main(){
  vec2 uv=vUv;
  float t = Tthin(uv);
  float film = smoothstep(0.78, 0.98, t);
  float a = texture(uPrev, uv).r;
  float b = texture(uPrev, uv - vec2(0.0, 2.4/uRes.y)).r;
  float trail = max(a, b) * uDecay;
  fragColor = vec4(vec3(max(trail, film * uGrow)), 1.0);
}
`;

class SlimeBlob {
  constructor(x, y, r) {
    this.x = x;
    this.y = y;
    this.vx = (Math.random() - 0.5) * 0.008;
    this.vy = 0;
    this.r = r;
    this.ay = 1.25 + Math.random() * 0.5;
    this.stuck = 0;
    this.seed = Math.random() * 1000;
  }
}

function mergeBlobs(blobs, mul) {
  const out = [];
  const used = new Set();
  for (let i = 0; i < blobs.length; i++) {
    if (used.has(i)) continue;
    let b = blobs[i];
    for (let j = i + 1; j < blobs.length; j++) {
      if (used.has(j)) continue;
      const o = blobs[j];
      const d = Math.hypot(o.x - b.x, o.y - b.y);
      const lim = (b.r + o.r) * mul;
      if (d < lim && d > 1e-6) {
        const w1 = b.r * b.r,
          w2 = o.r * o.r,
          w = w1 + w2;
        const nb = new SlimeBlob((b.x * w1 + o.x * w2) / w, (b.y * w1 + o.y * w2) / w, Math.min(0.18, Math.sqrt(b.r * b.r + o.r * o.r) * 0.88));
        nb.vx = (b.vx * w1 + o.vx * w2) / w;
        nb.vy = (b.vy * w1 + o.vy * w2) / w;
        nb.ay = (b.ay * w1 + o.ay * w2) / w;
        b = nb;
        used.add(j);
      }
    }
    out.push(b);
  }
  return out;
}

function strands(blobs, s) {
  if (s < 1e-6) return;
  const n = blobs.length;
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const a = blobs[i],
        b = blobs[j];
      const dx = b.x - a.x,
        dy = b.y - a.y;
      const d = Math.hypot(dx, dy) + 1e-6;
      const R = (a.r + b.r) * 2.4;
      if (d < R) {
        const k = s * (1 - d / R) * 2e-4,
          nx = dx / d,
          ny = dy / d;
        a.vx -= nx * k;
        a.vy -= ny * k * 0.4;
        b.vx += nx * k;
        b.vy += ny * k * 0.4;
      }
    }
  }
}

function main() {
  const canvas = document.getElementById("c");
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false, powerPreference: "high-performance" });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(window.innerWidth, window.innerHeight);

  let W = window.innerWidth,
    H = window.innerHeight;
  const rtBg = new THREE.WebGLRenderTarget(W, H, { depthBuffer: false });
  const rtA = new THREE.WebGLRenderTarget(W, H, { depthBuffer: false });
  const rtB = new THREE.WebGLRenderTarget(W, H, { depthBuffer: false });
  let resRead = rtA,
    resWrite = rtB;
  for (const rt of [rtA, rtB]) {
    renderer.setRenderTarget(rt);
    renderer.clear();
  }
  renderer.setRenderTarget(null);

  const cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const quad = new THREE.PlaneGeometry(2, 2);

  const bgMat = new THREE.ShaderMaterial({
    glslVersion: THREE.GLSL3,
    vertexShader: bgVert,
    fragmentShader: bgFrag,
    uniforms: { uTime: { value: 0 } },
  });
  const bgSc = new THREE.Scene();
  bgSc.add(new THREE.Mesh(quad, bgMat));

  const slimeU = {
    uBg: { value: rtBg.texture },
    uResidue: { value: resRead.texture },
    uRes: { value: new THREE.Vector2(W, H) },
    uTime: { value: 0 },
    uN: { value: 0 },
    uP: { value: Array.from({ length: MAX_BLOBS }, () => new THREE.Vector2()) },
    uR: { value: new Float32Array(MAX_BLOBS) },
    uAy: { value: new Float32Array(MAX_BLOBS) },
    uEdgeNoise: { value: 0.55 },
    uThickContrast: { value: 0.78 },
    uRefraction: { value: 0.062 },
    uSpecI: { value: 1.4 },
    uFreI: { value: 0.9 },
    uFrePow: { value: 5.0 },
    uTintStr: { value: 0.42 },
    uChroma: { value: 0.004 },
    uTrailOp: { value: 0.95 },
  };
  const slimeMat = new THREE.ShaderMaterial({
    glslVersion: THREE.GLSL3,
    vertexShader: slimeVert,
    fragmentShader: slimeFrag,
    uniforms: slimeU,
    depthTest: false,
    depthWrite: false,
  });
  const slimeSc = new THREE.Scene();
  slimeSc.add(new THREE.Mesh(quad, slimeMat));

  const resU = {
    uPrev: { value: resRead.texture },
    uRes: { value: new THREE.Vector2(W, H) },
    uDecay: { value: 0.994 },
    uGrow: { value: 0.32 },
    uN: slimeU.uN,
    uP: slimeU.uP,
    uR: slimeU.uR,
    uAy: slimeU.uAy,
    uEdgeNoise: slimeU.uEdgeNoise,
    uTime: slimeU.uTime,
  };
  const resMat = new THREE.ShaderMaterial({
    glslVersion: THREE.GLSL3,
    vertexShader: resVert,
    fragmentShader: resFrag,
    uniforms: resU,
  });
  const resSc = new THREE.Scene();
  resSc.add(new THREE.Mesh(quad, resMat));

  const P = {
    viscosity: 0.9925,
    adhesion: 0.86,
    gravity: 0.028,
    strandStrength: 0.72,
    trailOpacity: 0.95,
    refractionStrength: 0.062,
    thicknessContrast: 0.78,
    specularIntensity: 1.4,
    fresnelIntensity: 0.9,
    edgeIrregularity: 0.55,
    trailDecay: 0.994,
    trailGrow: 0.32,
    tintStrength: 0.42,
    chroma: 0.004,
    mergeDist: 0.8,
    count: 6,
  };

  let blobs = [];
  function reset() {
    blobs = [];
    const n = Math.min(MAX_BLOBS, Math.max(1, Math.round(P.count)));
    for (let i = 0; i < n; i++) {
      blobs.push(new SlimeBlob(0.1 + Math.random() * 0.8, 0.15 + Math.random() * 0.35, 0.032 + Math.random() * 0.042));
    }
  }
  reset();

  const gui = new GUI({ title: "Glass-plane slime (optical)" });
  gui.add(P, "gravity", 0.006, 0.08, 0.002).name("gravity");
  gui.add(P, "viscosity", 0.985, 0.9995, 0.0005).name("viscosity");
  gui.add(P, "adhesion", 0.4, 0.98, 0.02).name("adhesion");
  gui.add(P, "strandStrength", 0, 1.5, 0.05).name("strandStrength");
  gui.add(P, "trailOpacity", 0.5, 1, 0.02).name("trailOpacity");
  gui.add(P, "trailDecay", 0.988, 0.998, 0.001).name("trailDecay");
  gui.add(P, "trailGrow", 0.1, 0.6, 0.02).name("trailGrow");
  gui.add(P, "refractionStrength", 0.02, 0.12, 0.002).name("refractionStrength");
  gui.add(P, "thicknessContrast", 0.4, 0.95, 0.02).name("thicknessContrast");
  gui.add(P, "specularIntensity", 0.2, 3, 0.05).name("specularIntensity");
  gui.add(P, "fresnelIntensity", 0.2, 2, 0.05).name("fresnelIntensity");
  gui.add(P, "edgeIrregularity", 0, 1.5, 0.03).name("edgeIrregularity");
  gui.add(P, "tintStrength", 0.1, 0.85, 0.02).name("tintStrength");
  gui.add(P, "chroma", 0, 0.012, 0.0005).name("chroma");
  gui.add(P, "mergeDist", 0.55, 1.2, 0.02).name("mergeDist");
  gui.add(P, "count", 1, MAX_BLOBS, 1).name("blobs").onFinishChange(reset);
  gui.add({ reset }, "reset").name("reset blobs");

  let last = performance.now();
  function frame(now) {
    requestAnimationFrame(frame);
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    const t = now * 0.001;
    bgMat.uniforms.uTime.value = t;
    slimeU.uTime.value = t;

    slimeU.uEdgeNoise.value = P.edgeIrregularity;
    slimeU.uThickContrast.value = P.thicknessContrast;
    slimeU.uRefraction.value = P.refractionStrength;
    slimeU.uSpecI.value = P.specularIntensity;
    slimeU.uFreI.value = P.fresnelIntensity;
    slimeU.uTintStr.value = P.tintStrength;
    slimeU.uChroma.value = P.chroma;
    slimeU.uTrailOp.value = P.trailOpacity;

    strands(blobs, P.strandStrength);

    const visc = P.viscosity,
      adh = P.adhesion;
    for (const b of blobs) {
      const sp = Math.hypot(b.vx, b.vy);
      const low = b.y < b.r + 0.12;
      b.vy += P.gravity * dt * 32 * (1.0 - adh * 0.25);
      b.vy *= visc;
      b.vx *= visc;
      if (low && sp < 0.015) {
        b.stuck = Math.min(1, b.stuck + dt * 2);
        b.vy *= 1 - adh * 0.5 * b.stuck;
        b.vx *= 1 - adh * 0.2 * b.stuck;
      } else b.stuck = Math.max(0, b.stuck - dt * 2.2);

      b.x += b.vx * dt * 22;
      b.y -= b.vy * dt * 22;

      b.x = Math.min(1 - b.r, Math.max(b.r, b.x));
      if (b.y < b.r) {
        b.y = b.r;
        b.vy *= -0.1 * adh;
      }
      if (b.y > 1 - b.r) {
        b.y = 1 - b.r;
        b.vy *= -0.06 * adh;
        b.vx *= 0.9;
      }

      b.ay = Math.min(2.6, Math.max(1.1, 1.2 + Math.abs(b.vy) * 380 + b.r * 4));
    }
    blobs = mergeBlobs(blobs, P.mergeDist);

    const n = Math.min(blobs.length, MAX_BLOBS);
    slimeU.uN.value = n;
    for (let i = 0; i < MAX_BLOBS; i++) {
      if (i < n) {
        slimeU.uP.value[i].set(blobs[i].x, blobs[i].y);
        slimeU.uR.value[i] = blobs[i].r;
        slimeU.uAy.value[i] = blobs[i].ay;
      } else {
        slimeU.uR.value[i] = 1e-4;
        slimeU.uAy.value[i] = 1;
      }
    }

    renderer.setRenderTarget(rtBg);
    renderer.render(bgSc, cam);

    resU.uPrev.value = resRead.texture;
    resU.uDecay.value = P.trailDecay;
    resU.uGrow.value = P.trailGrow;
    resU.uRes.value.set(W, H);
    renderer.setRenderTarget(resWrite);
    renderer.render(resSc, cam);

    slimeU.uBg.value = rtBg.texture;
    slimeU.uResidue.value = resWrite.texture;
    slimeU.uRes.value.set(W, H);
    renderer.setRenderTarget(null);
    renderer.render(slimeSc, cam);

    const tmp = resRead;
    resRead = resWrite;
    resWrite = tmp;
    resU.uPrev.value = resRead.texture;
  }
  requestAnimationFrame(frame);

  window.addEventListener("resize", () => {
    W = window.innerWidth;
    H = window.innerHeight;
    renderer.setSize(W, H);
    rtBg.setSize(W, H);
    rtA.setSize(W, H);
    rtB.setSize(W, H);
    slimeU.uRes.value.set(W, H);
    resU.uRes.value.set(W, H);
  });
}

main();

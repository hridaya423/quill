#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

static float3 linear(half4 c) { return pow(float3(c.rgb), 2.2); }

struct Sky {
    float h;
    float R;
    float2 c;
    float sun;
    float dawn;
    float time;
    float3 night, blue, sky;
};

static float3 above(float2 p, float d, Sky s) {
    float alt = max(d, 0.0) / s.h;
    float x = (p.x - s.sun) / s.h;
    float focus = exp(-abs(x) / 0.5);
    float3 deep = s.blue * float3(0.1, 0.13, 0.2);
    float3 col = mix(s.night * 0.9, s.night * 0.35, smoothstep(0.0, 1.1, alt));
    col += deep * (0.35 + 1.3 * s.dawn) * exp(-alt / 0.5) * exp(-x * x / 2.6);
    float3 scatter = exp(-alt / float3(0.028, 0.05, 0.11));
    col += s.dawn * s.sky * 1.5 * scatter * (0.3 + 0.7 * focus) * exp(-x * x / 1.1);
    col += s.dawn * s.blue * 0.5 * exp(-alt / 0.3) * exp(-x * x / 1.8);
    float folds = 0.0;
    for (int i = 0; i < 5; i++) {
        float k = float(i);
        float seed = hash(float2(k, 3.7));
        float cx = (k - 2.0) * 0.3 + 0.07 * sin(s.time * 0.045 + k * 1.7);
        float warp = 0.09 * (noise(float2(alt * 2.6 + k * 7.1, s.time * 0.025 + k)) - 0.5);
        float w = 0.045 + 0.05 * seed;
        float band = exp(-pow((x - cx + warp) / w, 2.0));
        float rise = smoothstep(0.0, 0.05, alt) * exp(-alt / (0.2 + 0.18 * seed));
        folds += band * rise * (0.65 + 0.35 * sin(s.time * 0.06 + k * 2.3));
    }
    col += s.dawn * mix(s.blue, s.sky, 0.55) * 0.16 * folds * exp(-x * x / 1.3);
    col += s.dawn * 2.4 * exp(-alt / 0.0024) * (0.2 + 0.8 * focus);
    col += s.dawn * s.sky * 1.1 * exp(-alt / 0.011) * (0.25 + 0.75 * focus);
    return col;
}

static float3 below(float2 p, float d, Sky s) {
    float depth = max(-d, 0.0) / s.h;
    float x = (p.x - s.sun) / s.h;
    float focus = exp(-abs(x) / 0.5);
    float2 rel = p - s.c;
    float angle = atan2(rel.x, -rel.y);
    float2 surface = float2(angle * s.R / s.h * 2.2 + s.time * 0.012, depth * 7.0);
    float bands = fbm(surface * float2(1.0, 2.6) + float2(0.0, s.time * 0.01));
    float3 deep = s.blue * float3(0.1, 0.13, 0.2);
    float3 body = s.night * 0.28 + deep * 0.12;
    float limb = exp(-depth / 0.07);
    body += s.dawn * mix(s.blue, s.sky, 0.25) * (0.05 + 0.9 * smoothstep(0.42, 0.78, bands)) * limb * exp(-x * x / 0.6);
    body += s.dawn * s.blue * 0.7 * exp(-depth / 0.03) * (0.3 + 0.7 * focus);
    body += s.dawn * s.sky * 1.4 * exp(-depth / 0.005) * (0.25 + 0.75 * focus);
    body += s.dawn * mix(s.sky, float3(1.0), 0.5) * 0.7 * exp(-pow(x / 0.18, 2.0) - depth / 0.012) * (0.55 + 0.45 * bands);
    return body;
}

static float3 scene(float2 p, Sky s) {
    float d = length(p - s.c) - s.R;
    float edge = s.h * 0.0012;
    if (d > edge) return above(p, d, s);
    if (d < -edge) return below(p, d, s);
    return mix(below(p, d, s), above(p, d, s), smoothstep(-edge, edge, d));
}

static float coverage(float2 p, texture2d<half> sharp, float4 q, float4 u, float reveal, float letters) {
    constexpr sampler linearly(address::clamp_to_zero, filter::linear);
    return max(sharp.sample(linearly, (p - q.xy) / q.zw).r * reveal,
               sharp.sample(linearly, (p - u.xy) / u.zw).g * letters);
}

[[ stitchable ]] half4 horizon(float2 position, half4 current, float2 size, float time, float dawn, float drift,
                               half4 night, half4 blue, half4 sky,
                               texture2d<half> sharp,
                               float4 q, float4 u, float reveal, float letters) {
    float w = size.x, h = size.y;
    Sky s;
    s.h = h;
    s.R = max(w * 1.7, h * 1.6) * 0.5;
    float top = h * (1.08 - 0.26 * dawn);
    s.c = float2(w * 0.5 + drift, top + s.R);
    s.sun = s.c.x;
    s.dawn = dawn;
    s.time = time;
    s.night = linear(night);
    s.blue = linear(blue);
    s.sky = linear(sky);

    float2 p = position;
    float3 col = scene(p, s);

    if (reveal + letters > 0.001) {
        float m = coverage(p, sharp, q, u, reveal, letters);
        float e = 1.1;
        float2 slope = float2(coverage(p + float2(e, 0), sharp, q, u, reveal, letters) - coverage(p - float2(e, 0), sharp, q, u, reveal, letters),
                              coverage(p + float2(0, e), sharp, q, u, reveal, letters) - coverage(p - float2(0, e), sharp, q, u, reveal, letters));
        float edge = saturate(length(slope));
        if (m > 0.002 || edge > 0.002) {
            float2 inward = slope / (length(slope) + 1e-4);
            float3 glass = scene(p + inward * h * 0.01 + float2(w * 0.03, h * 0.13), s);
            glass = mix(glass, float3(0.02, 0.19, 0.45), 0.3);
            glass *= float3(0.89, 0.97, 1.005);
            col = mix(col, glass, m * 0.9);
            float2 toSun = normalize(float2(s.sun, top) - p);
            float key = max(dot(inward, normalize(float2(1.0, 1.0))), 0.0);
            float sunlit = max(dot(inward, -toSun), 0.0);
            float shade = max(dot(inward, normalize(float2(-1.0, -1.0))), 0.0) * (1.0 - sunlit);
            col += edge * key * mix(s.sky, float3(1.0), 0.3) * 0.32;
            col += edge * sunlit * s.sky * 0.22 * dawn;
            col *= 1.0 - edge * shade * float3(0.3, 0.24, 0.12);
        }
    }

    float2 v = (p / size - 0.5) * float2(1.0, 1.25);
    col *= 1.0 - 0.32 * pow(saturate(length(v) * 1.15), 2.4);
    col = 1.0 - exp(-col * 1.08);
    col = pow(max(col, 0.0), 1.0 / 2.2);
    col += (hash(p + fract(time) * 61.0) + hash(p * 1.37 + fract(time * 1.3) * 17.0) - 1.0) / 255.0;
    return half4(half3(saturate(col)), 1.0);
}

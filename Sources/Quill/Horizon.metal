// The ray field is ported from Paper Shaders' God Rays (Apache-2.0, https://github.com/paper-design/shaders).
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

static float rays(float2 uv, float r, float freq, float power) {
    float a = atan2(uv.y, uv.x);
    float left = pow(noise(float2(a * freq, r)), power);
    float right = pow(noise(float2(fract(a / (2.0 * M_PI_F)) * 2.0 * M_PI_F * freq, r)), power);
    return mix(right, left, smoothstep(-0.15, 0.15, uv.x));
}

[[ stitchable ]] half4 horizon(float2 position, half4 current, float2 size, float time, float dawn, float drift,
                               half4 night, half4 blue, half4 sky) {
    float w = size.x, h = size.y;
    float R = max(w * 1.7, h * 1.6) * 0.5;
    float rim = h * (1.08 - 0.26 * dawn);
    float2 c = float2(w * 0.5 + drift, rim + R);
    float2 p = position;
    float d = length(p - c) - R;

    float3 col = float3(night.rgb);
    float2 top = float2(c.x, rim);
    float spread = length((p - top) / float2(1.4, 1.0));
    col += float3(blue.rgb) * 0.34 * dawn * exp(-spread / (h * 0.55));
    float out = max(d, 0.0);
    col += float3(sky.rgb) * 0.85 * dawn * exp(-out / (h * 0.022));
    col += float3(blue.rgb) * 0.42 * dawn * exp(-out / (h * 0.16));
    col += float3(sky.rgb) * 0.3 * dawn * exp(-length(p - top) / (h * 0.09));

    if (d > 0.0) {
        float2 uv = (p - top) / h;
        float t = 0.06 * time;
        float radius = length(uv);
        float shaft = rays(uv, radius * 1.4 - 3.0 * t, 16.0, 2.2) * rays(uv, radius * 2.2 - 2.0 * t, 12.0, 2.2);
        float lift = smoothstep(0.0, 0.12, -uv.y + 0.02);
        col += float3(sky.rgb) * shaft * 0.22 * dawn * lift * exp(-radius / 0.7);
    } else {
        float depth = -d;
        float lit = min(1.0, dawn * 1.6);
        float3 body = mix(float3(blue.rgb) * 0.55, float3(night.rgb), smoothstep(0.0, h * 0.42, depth));
        float angle = atan2(p.x - c.x, c.y - p.y);
        float2 surface = float2(angle * R / h * 2.2 + time * 0.012, depth / h * 7.0);
        float bands = fbm(surface * float2(1.0, 2.6) + float2(0, time * 0.01));
        float limb = exp(-depth / (h * 0.11));
        body += float3(sky.rgb) * (bands - 0.42) * 0.7 * limb;
        body += float3(blue.rgb) * 0.9 * exp(-depth / (h * 0.03));
        body += float3(sky.rgb) * 1.1 * exp(-depth / (h * 0.0045));
        col = mix(col, body, lit * smoothstep(0.0, h * 0.004, depth));
    }

    col += (hash(p + fract(time) * 61.0) - 0.5) / 255.0 * 2.5;
    return half4(half3(clamp(col, 0.0, 1.0)), 1.0);
}

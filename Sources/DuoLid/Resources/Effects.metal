#include <metal_stdlib>
using namespace metal;

struct VertexOut { float4 position [[position]]; float2 uv; };
struct EffectUniforms {
    float progress; float perspective; float shade; float glow;
    float spread; float aspect; float corners; float blurGradient;
    float bleed;
    float4 colorA; float4 colorB; float4 colorC;
};

vertex VertexOut fullScreenVertex(uint id [[vertex_id]]) {
    const float2 positions[] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    VertexOut out;
    out.position = float4(positions[id], 0, 1);
    out.uv = float2((positions[id].x + 1) * 0.5, (1 - positions[id].y) * 0.5);
    return out;
}

float bloom(float2 uv, float2 center, float radius, float aspect) {
    float2 d = (uv - center) * float2(aspect, 1);
    return exp(-dot(d, d) / (radius * radius));
}

float3 cornerLight(float2 uv, constant EffectUniforms &u) {
    float radius = mix(0.17, 0.64, u.spread);
    float upper = u.corners < 0.5 || u.corners > 1.5 ? 1.0 : 0.0;
    float lower = u.corners < 1.5 ? 1.0 : 0.0;
    float drift = u.progress * 0.055;
    float3 light = u.colorA.rgb * bloom(uv, float2(-0.035, -0.04 + drift), radius, u.aspect) * upper;
    light += u.colorB.rgb * bloom(uv, float2(1.025, -0.01), radius * 0.84, u.aspect) * upper;
    light += u.colorC.rgb * bloom(uv, float2(-0.015, 1.04 - drift), radius * 0.93, u.aspect) * lower;
    light += u.colorA.rgb * bloom(uv, float2(1.035, 1.025), radius, u.aspect) * lower;
    // Lift saturation toward a pale, airy light while retaining the chosen hue.
    return mix(light, float3(max(light.r, max(light.g, light.b))), 0.58);
}

fragment float4 duoComposite(VertexOut in [[stage_in]], texture2d<float> original [[texture(0)]],
                             texture2d<float> blurred [[texture(1)]],
                             texture2d<float> softBlur [[texture(2)]],
                             constant EffectUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.uv;
    if (u.progress <= 0.00001) { return original.sample(s, uv); }
    // Inverse-project a plane rotating away around its bottom-center hinge.
    // The bottom edge is fixed; the top edge moves down and becomes narrower.
    float theta = u.perspective * u.progress;
    float sine = sin(theta), cosine = cos(theta);
    float bottomDistance = 1.0 - uv.y;
    float denominator = cosine - bottomDistance * sine / 2.4;
    float sourceHeight = bottomDistance / max(denominator, 0.0001);
    float depth = 1.0 + sourceHeight * sine / 2.4;
    float2 projected = float2((uv.x - 0.5) * depth + 0.5, 1.0 - sourceHeight);
    float feather = 0.001 + u.progress * 0.023;
    float inside = theta < 0.00001 ? 1.0 :
        smoothstep(-feather, feather, projected.x) * (1.0 - smoothstep(1.0 - feather, 1.0 + feather, projected.x)) *
        smoothstep(-feather, feather * 2.0, projected.y) * step(0.0001, denominator);
    float3 base = float3(0.0), background = float3(0.0);
    if (inside > 0.0) {
        float front = mix(-0.18, 1.18, u.progress);
        float coverage = (1.0 - smoothstep(front - 0.18, front + 0.18, projected.y)) * smoothstep(0.0, 0.025, u.progress);
        float3 sharp = coverage < 1.0 ? original.sample(s, projected).rgb : float3(0.0);
        float3 diffuse = coverage > 0.0 ? mix(blurred.sample(s, projected).rgb, softBlur.sample(s, projected).rgb,
                                             smoothstep(0.0, 1.0, projected.y) * u.blurGradient) : float3(0.0);
        base = mix(sharp, diffuse, coverage);
        base *= 1.0 - u.shade * u.progress * (0.45 + 0.55 * (1.0 - clamp(projected.y, 0.0, 1.0)));
        if (u.glow > 0.0) {
            float3 glow = cornerLight(projected, u);
            float strength = u.glow * pow(u.progress, 0.85) * 0.88;
            base = 1.0 - (1.0 - base) * (1.0 - clamp(glow * strength, 0.0, 0.88));
        }
    }
    if (inside < 1.0) {
        // Light softly spills from the projected edge into the space behind it.
        // Distance is measured in screen space, so the halo keeps a soft width as it folds.
        float topScale = 1.0 / (1.0 + sine / 2.4);
        float topY = 1.0 - cosine * topScale;
        float alongSide = clamp((uv.y - topY) / max(1.0 - topY, 0.0001), 0.0, 1.0);
        float halfWidth = 0.5 * mix(topScale, 1.0, alongSide);
        float2 outside = float2(max(abs(uv.x - 0.5) - halfWidth, 0.0) * u.aspect, max(topY - uv.y, 0.0));
        float haloWidth = mix(0.055, 0.215, u.spread);
        float distanceSquared = dot(outside, outside);
        float nearHalo = exp(-distanceSquared / (haloWidth * haloWidth));
        float farHalo = exp(-distanceSquared / (haloWidth * haloWidth * 3.61));
        // A bright, soft core and a broader falloff read as light bleeding from the
        // display, instead of an outline. Both follow the lid without a hard onset.
        float halo = (nearHalo * 0.76 + farHalo * 0.24) * smoothstep(0.015, 0.55, u.progress) * u.bleed * 1.7;
        // Above the folding edge, sample along that edge directly. Extrapolating the
        // inverse perspective up here would split the halo down its center.
        float2 edgeUV = uv.y < topY ? float2(clamp((uv.x - 0.5) / topScale + 0.5, 0.0, 1.0), 0.0) : clamp(projected, 0.0, 1.0);
        float luminance = dot(blurred.sample(s, edgeUV).rgb, float3(0.2126, 0.7152, 0.0722));
        float3 ambient = float3(luminance * 0.18);
        float upper = u.corners < 0.5 || u.corners > 1.5 ? 1.0 : 0.0;
        float lower = u.corners < 1.5 ? 1.0 : 0.0;
        float3 upperWash = mix(u.colorA.rgb, u.colorB.rgb, smoothstep(0.0, 1.0, edgeUV.x)) * upper;
        float3 lowerWash = mix(u.colorC.rgb, u.colorA.rgb, smoothstep(0.0, 1.0, edgeUV.x)) * lower;
        float3 wash = mix(upperWash, lowerWash, smoothstep(0.0, 1.0, edgeUV.y));
        wash = mix(wash, float3(max(wash.r, max(wash.g, wash.b))), 0.58);
        float3 coloredSpill = (cornerLight(edgeUV, u) * 0.76 + wash * 0.24) * u.glow * 0.62;
        background = float3(0.014) + (ambient + coloredSpill) * halo;
    }
    base = mix(background, base, inside);
    // Sub-level spatial dithering keeps long, dim light gradients from banding.
    float noise = fract(52.9829189 * fract(dot(floor(in.position.xy), float2(0.06711056, 0.00583715)))) - 0.5;
    base += noise / 255.0 * (1.0 - inside) * smoothstep(0.0, 0.1, u.progress);
    return float4(base, 1);
}

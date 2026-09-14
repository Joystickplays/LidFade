#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// ---------------------------------------------------------------------------
// Progressive Gaussian blur. Separable: apply progressiveBlurH then
// progressiveBlurV. Cost is 2 * kTaps samples/px, independent of radius.
// ---------------------------------------------------------------------------

constexpr constant int   kHalfTaps = 8;    // 17 taps per axis
constexpr constant float kSigmas   = 3.0;  // truncate kernel at 3σ (99.7%)

// Radius ramp: max at the top, 0 at the hinge.
static inline float radiusAt(float2 position, float2 size, float progress, float maxRadius) {
    float t = saturate(1.0 - position.y / max(size.y, 1.0)); // 1 top -> 0 bottom
    t *= t;                                                  // ease-in; remove for linear
    return t * progress * maxRadius;
}

static inline half4 blurAxis(SwiftUI::Layer layer, float2 position,
                             float2 size, float radius, float2 axis) {
    if (radius < 0.5) {
        return layer.sample(position);
    }

    // Derive σ from the truncation radius so weights and spacing always agree.
    float sigma      = radius / kSigmas;
    float step       = radius / float(kHalfTaps);   // spacing == σ / 2.67 -> no banding
    float twoSigmaSq = 2.0 * sigma * sigma;

    float2 lo = float2(0.5);
    float2 hi = size - 0.5;

    float4 sum  = float4(0.0);
    float  wsum = 0.0;

    for (int i = -kHalfTaps; i <= kHalfTaps; ++i) {
        float  d = float(i) * step;
        float  w = exp(-(d * d) / twoSigmaSq);
        float2 p = clamp(position + axis * d, lo, hi);   // edge-clamp, no dark halo
        sum  += float4(layer.sample(p)) * w;             // accumulate in float
        wsum += w;
    }
    return half4(sum / wsum);
}

[[ stitchable ]]
half4 progressiveBlurH(float2 position, SwiftUI::Layer layer, float2 size,
                       float progress, float maxRadius) {
    float r = radiusAt(position, size, progress, maxRadius);
    return blurAxis(layer, position, size, r, float2(1.0, 0.0));
}

// Final pass: vertical blur + fade toward black + soft top-edge dissolve.
// The tilt recedes the plane's top edge, which otherwise leaves a hard cut
// against the backing black. `edgeTilt` (degrees, from the eased lid delta)
// ramps the dissolve: 0 at rest (overlay seamless on appear), saturating
// by 25°.
[[ stitchable ]]
half4 progressiveBlurV(float2 position, SwiftUI::Layer layer, float2 size,
                       float progress, float maxRadius, float edgeTilt,
                       float linkToBlur, float linkMultiplier, float gateDegrees,
                       float topSpanFrac, float sideSpanFrac) {
    float r = radiusAt(position, size, progress, maxRadius);
    half4 blurred = blurAxis(layer, position, size, r, float2(0.0, 1.0));
    float3 color = mix(float3(blurred.rgb), float3(0.0), saturate(progress));

    float tiltMag = abs(edgeTilt);

    // Driver select. linkToBlur = 1: the melt rides the blur's own curve —
    // driven by `progress` scaled by linkMultiplier, so >1 melts ahead of the
    // blur, <1 trails it, 1 is lockstep. linkToBlur = 0: the dissolve runs on
    // its own tilt gate (gateDegrees).
    float drive = mix(saturate(tiltMag / max(gateDegrees, 0.01)),
                      saturate(progress * max(linkMultiplier, 0.0)),
                      linkToBlur);

    // Same select for how fast the band's reach grows toward its max spans.
    float growth = mix(saturate(tiltMag / 60.0),
                       saturate(progress * max(linkMultiplier, 0.0)),
                       linkToBlur);

    // Reach grows from a floor of 25% of the tuned max up to the full
    // slider value. The floor matters: if the span collapsed toward zero
    // early on, the band would become a razor-thin full-strength box
    // instead of a soft gradient.
    float topSpan  = size.y * topSpanFrac  * mix(0.25, 1.0, growth);
    float sideSpan = size.x * sideSpanFrac * mix(0.25, 1.0, growth);

    // smoothstep, not linear "1 - x/span": guarantees exactly 1.0 at the
    // boundary and exactly 0.0 past the span, regardless of half-pixel
    // sample-center offsets.
    float topFade  = 1.0 - smoothstep(0.0, topSpan,  position.y);
    float fadeL    = 1.0 - smoothstep(0.0, sideSpan, position.x);
    float fadeR    = 1.0 - smoothstep(0.0, sideSpan, size.x - position.x);
    float sideFade = max(fadeL, fadeR);

    float edgeFade = drive * max(topFade, sideFade);

    // Absolute, size-independent safety net: force full fade within the
    // last couple of physical pixels no matter what the % math above
    // produced. This guarantees zero residue right at the polygon boundary.
    float hardMarginPx = 2.0;
    float hardTop = 1.0 - smoothstep(0.0, hardMarginPx, position.y);
    float hardL   = 1.0 - smoothstep(0.0, hardMarginPx, position.x);
    float hardR   = 1.0 - smoothstep(0.0, hardMarginPx, size.x - position.x);
    edgeFade = max(edgeFade, drive * max(hardTop, max(hardL, hardR)));

    // Fade alpha *and* color together, premultiplied — the geometric edge
    // of the transformed quad dissolves into transparency instead of
    // terminating as an opaque near-black rectangle. Crucially the incoming
    // alpha is preserved: the layer was clipped to the display's rounded
    // corners upstream, and blurred.a carries that coverage through the
    // blur (premultiplied accumulation). Overwriting alpha here, as this
    // shader used to, would square the corners back off.
    float  inAlpha  = float(blurred.a);
    float  outAlpha = inAlpha * (1.0 - edgeFade);
    float3 outColor = color * (1.0 - edgeFade);

    return half4(half3(outColor), half(outAlpha));
}
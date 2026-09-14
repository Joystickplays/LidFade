import SwiftUI
import Combine

struct FadeOverlayView: View {
    @ObservedObject var model: FadeOverlayModel
    /// Live tuning sliders (dissolve gate/depth) — observed so moving a
    /// slider reshapes the overlay immediately.
    @ObservedObject var tuning: OverlayMotionSmoother

    /// Max blur radius (px) applied at the very top of the image at progress 1.
    /// Default only — the live value comes from the smoother (maxBlurRadius).
    var maxBlurRadius: Double = 45
    /// SwiftUI's rotation3DEffect perspective term — larger reads as "closer to
    /// the lens" (more dramatic foreshortening), smaller as flatter/more distant.
    var perspective: Double = 0.35
    /// Corner radius matching the built-in display's physical rounding. There's
    /// no public API for this — ~10pt is the accepted value for MacBook panels.
    /// Applied unconditionally so the overlay always mirrors the screen.
    var displayCornerRadius: Double = 10

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Opaque backing — as the picture tilts/scales, edges reveal
                // black instead of the desktop behind the window.
                Color.black

                if let image = model.image {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        // Clip BEFORE the blur passes: a .fill image overflows
                        // its frame, and the shader must receive a layer whose
                        // bounds == geo.size or its radius ramp / edge clamps
                        // compute against the wrong dimensions (stretched,
                        // unblurred edges). Rounded to the display's corner
                        // radius so the overlay mirrors the physical panel —
                        // the alpha this creates survives the V shader, which
                        // multiplies its dissolve into the incoming alpha.
                        // The stretch/tilt below still grow past the frame —
                        // transforms aren't re-clipped.
                        .clipShape(
                            RoundedRectangle(cornerRadius: displayCornerRadius, style: .continuous),
                            style: FillStyle(eoFill: false, antialiased: true)
                        )
                        // Separable progressive blur: horizontal pass, then
                        // vertical pass. maxSampleOffset stays .zero on
                        // purpose — the kernel edge-clamps all sampling to
                        // [0.5, size-0.5] internally, so it never reads
                        // outside the base bounds. Declaring a non-zero
                        // offset makes SwiftUI allocate padded intermediate
                        // textures for the chain, and that padding leaks
                        // into the visible output as a blurred "extension"
                        // with a hard edge.
                        .layerEffect(
                            ShaderLibrary.default.progressiveBlurH(
                                .float2(Float(geo.size.width), Float(geo.size.height)),
                                .float(Float(model.progress)),
                                .float(Float(tuning.maxBlurRadius))
                            ),
                            maxSampleOffset: .zero
                        )
                        .layerEffect(
                            ShaderLibrary.default.progressiveBlurV(
                                .float2(Float(geo.size.width), Float(geo.size.height)),
                                .float(Float(model.progress)),
                                .float(Float(tuning.maxBlurRadius)),
                                .float(Float(model.tiltDegrees)),
                                .float(tuning.dissolveLinkedToBlur ? 1.0 : 0.0),
                                .float(Float(tuning.dissolveLinkMultiplier)),
                                .float(Float(tuning.dissolveGateDegrees)),
                                .float(Float(tuning.dissolveTopSpan)),
                                .float(Float(tuning.dissolveSideSpan))
                            ),
                            maxSampleOffset: .zero
                        )
                        // Re-mask AFTER the blur passes. The Gaussian kernel
                        // (up to maxBlurRadius at the top) averages opaque
                        // pixels from inside the image and smears them past
                        // the rounded corner arcs — the pre-blur clip can't
                        // prevent that, so the rounded shape is applied again
                        // to the blurred output, cutting the bleed off clean.
                        .clipShape(
                            RoundedRectangle(cornerRadius: displayCornerRadius, style: .continuous)
                        )
                        // Flatten the shader output (with its premultiplied
                        // alpha) into a single texture BEFORE the geometric
                        // transforms composite it.
                        .compositingGroup()
                        // Vertical stretch from the hinge (bottom edge): 1 at
                        // rest → 1 + amount at progress 1, on its own ease-in
                        // curve. Bottom stays pinned, top grows upward.
                        .scaleEffect(x: 1, y: model.stretchScale, anchor: .bottom)
                        // `tiltDegrees` is the real physical delta the lid has rotated
                        // away from its anchor point (positive as it closes). Rotating
                        // the content by that same amount about the hinge axis (the
                        // bottom edge) tips the top away from the viewer, matching
                        // the lid folding away as it closes.
                        .rotation3DEffect(
                            .degrees(model.tiltDegrees),
                            axis: (x: 1, y: 0, z: 0),
                            anchor: .bottom,
                            perspective: perspective
                        )
                }
                // The dim used to live here as Color.black.opacity(progress);
                // progressiveBlurV now mixes the image toward black itself.
                // The opaque backing at the top of the ZStack is the only
                // black layer left — it fills the gaps when tilt/stretch
                // reveals edges (a shader can't paint outside its layer).
            }
        }
        .ignoresSafeArea()
        // Every value above is set directly by OverlayMotionSmoother's lerp loop.
        // This guarantees SwiftUI never layers its own implicit animation on top
        // of that — what you see is exactly the smoothed value, nothing else.
        .transaction { $0.disablesAnimations = true }
    }
}

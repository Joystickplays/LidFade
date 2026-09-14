import Foundation
import Combine

/// Separates "the true, degree-driven target" from "what's actually on screen."
///
/// `targetProgress` / `targetTiltDegrees` are set directly from live angle
/// readings elsewhere (never touched here) — this class only continuously lerps
/// the rendered `progress` / `tiltDegrees` toward whatever that target currently
/// is, every tick: `a + (b - a) * lerpFactor`. Because it's re-evaluated against
/// a live target on every frame rather than run for a fixed duration, it's
/// always interruptible — if the target changes mid-glide (lid pushed again,
/// or released), it simply redirects from wherever it currently is.
final class OverlayMotionSmoother: ObservableObject {
    @Published private(set) var progress: Double = 0       // 0...1, drives blur + dim (stays linear)
    @Published private(set) var tiltDegrees: Double = 0     // curved degrees, drives rotation3DEffect
    @Published private(set) var stretchScale: Double = 1.0  // 1.0 → 1 + stretchAmount, drives scaleEffect

    /// Tilt response curve — ease-IN (not out). 1 = linear (1:1 with the lid),
    /// >1 = slow off the anchor, increasingly aggressive as it closes.
    /// Applied as: curved = linear * progress^(exponent-1),
    /// so endpoints are preserved (0 at rest, full tilt at progress 1).
    @Published var tiltExponent: Double = 1.6

    /// Stretch response — independent ease-IN curve, same family as tilt.
    /// stretchExponent shapes WHEN it grows (1 = linear, higher = later),
    /// stretchAmount sets HOW MUCH (fraction taller at progress 1).
    @Published var stretchExponent: Double = 2.59
    @Published var stretchAmount: Double = 2.0

    /// Max blur radius (px) at the very top of the screen at progress 1 —
    /// the "top blur power" that the progressive ramp and (in linked mode)
    /// the dissolve both scale from.
    @Published var maxBlurRadius: Double = 45

    /// Edge dissolve tuning (consumed by progressiveBlurV).
    /// gateDegrees: tilt at which the image edge is FULLY faded — low = edges
    /// vanish almost immediately, high = dissolve waits for a deeper close.
    /// top/sideSpan: how far the melt reaches inward at full tilt, as a
    /// fraction of screen height/width. The dissolve is exactly zero at rest.
    /// Dissolve driver. Linked = the melt follows the blur's own curve
    /// (progress-driven, so more blur = more dissolve, no separate gate).
    /// Unlinked = the dissolve runs on its own tilt-based gate/spans below.
    @Published var dissolveLinkedToBlur: Bool = true
    /// Linked mode only: scales how strongly the dissolve responds to the
    /// blur's progress curve. 1 = in lockstep, >1 = melt leads the blur,
    /// <1 = melt lags behind it.
    @Published var dissolveLinkMultiplier: Double = 1.0
    /// Unlinked mode only: tilt at which the image edge is FULLY faded.
    @Published var dissolveGateDegrees: Double = 0.75
    /// Max melt reach at full tilt/progress, as a fraction of height/width
    /// (applies in both modes — "how much" is always yours to tune).
    @Published var dissolveTopSpan: Double = 0.30
    @Published var dissolveSideSpan: Double = 0.12

    /// Fraction of the remaining distance to close per tick. Higher = snappier,
    /// lower = floatier. 0.25 at 60Hz settles in a few hundred ms.
    @Published var lerpFactor: Double = 0.25

    var targetProgress: Double = 0
    var targetTiltDegrees: Double = 0

    /// Linear (uncurved) tilt being chased — the curve is derived from this
    /// plus the smoothed progress on every tick, so dragging the exponent
    /// slider reshapes the visible tilt within one frame, no re-lerp needed.
    private var linearTiltDegrees: Double = 0

    private var timer: DispatchSourceTimer?

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        progress = lerp(progress, targetProgress, lerpFactor)
        linearTiltDegrees = lerp(linearTiltDegrees, targetTiltDegrees, lerpFactor)

        // Snap the last little bit so it actually settles at exactly 0 / target
        // instead of asymptotically crawling forever.
        if abs(progress - targetProgress) < 0.0008 { progress = targetProgress }
        if abs(linearTiltDegrees - targetTiltDegrees) < 0.02 { linearTiltDegrees = targetTiltDegrees }

        tiltDegrees = curvedTilt(linear: linearTiltDegrees, progress: progress, exponent: tiltExponent)
        stretchScale = curvedStretch(progress: progress, amount: stretchAmount, exponent: stretchExponent)
    }

    /// Ease-IN power curve (not ease-out): exponent 1 = linear, 2 = quadratic, etc.
    /// Small progress → disproportionately small tilt; tilt catches up late.
    /// Endpoints preserved: 0 when resting, full linear tilt at progress 1.
    private func curvedTilt(linear: Double, progress: Double, exponent: Double) -> Double {
        guard linear > 0, progress > 0.0001, exponent != 1 else { return max(linear, 0) }
        return linear * pow(progress, exponent - 1)
    }

    /// Ease-IN vertical stretch: 1 at rest → 1 + amount at progress 1.
    /// Same curve family as the flip, independently tunable.
    private func curvedStretch(progress: Double, amount: Double, exponent: Double) -> Double {
        guard progress > 0.0001, amount > 0 else { return 1.0 }
        return 1.0 + amount * pow(progress, exponent)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

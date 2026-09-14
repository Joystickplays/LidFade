# AGENTS.md

Notes for future agents working on LidFade. Read this before
touching anything — the codebase has several load-bearing decisions that look
like mistakes and are not.

## What this is

macOS app that overlays a screenshot of the current screen when the physical
lid starts closing, rendering it folding away (progressive blur + dim +
stretch + 3D tilt) driven by the real lid-angle sensor. Swift 6.3, SwiftUI,
Metal `.layerEffect` shaders, IOKit HID.

## Architecture (data flows strictly downward)

```
LidAngleSensor        IOKit HID poll, 60 Hz, publishes angleDegrees
  → LidStateMachine   angle → intent (idle/armed/closing), pure-ish logic
    → OverlayMotionSmoother  targets → 60 Hz lerped rendered values
      → FadeOverlayModel/View what's on screen
```

- `AppDelegate.handlePhaseChange` is the ONLY place raw targets are set.
  `AppDelegate.handleMotionUpdate` is the only place the overlay is updated
  and dismissed (on settle-at-zero, not on phase change — that's what makes
  cancel glide).
- The state machine has NO timers and NO animation. Progress is a pure
  function of angle. All time/curves live in the smoother.
- Tunables are `@Published` on `LidStateMachine` / `OverlayMotionSmoother`
  and bound directly to sliders in `ContentView`. The overlay view observes
  the smoother, so slider changes reshape the effect live mid-animation.
- `OverlayWindowController` takes the smoother in its init (the view needs
  live tuning values); it's a `lazy var` in AppDelegate for that reason.

## Load-bearing gotchas — do not "clean these up"

1. **`import Combine` is required** in files using `ObservableObject`/
   `@Published`/`@ObservedObject`. The target sets
   `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`, so member
   visibility is strict. Missing import = confusing conformace errors.
2. **`maxSampleOffset: .zero` on both `.layerEffect` calls, on purpose.**
   Non-zero makes SwiftUI allocate padded intermediate textures and the
   padding leaks in as a blurred "extension" with a hard edge. The shaders
   edge-clamp internally; they never read out of bounds.
3. **The image must be clipped to `geo.size` before the blur passes.** A
   `.aspectRatio(.fill)` image overflows its frame; if the shader's layer
   bounds ≠ `geo.size`, the radius ramp and edge clamps compute against the
   wrong dimensions (stretched, unblurred edges).
4. **The rounded-corner clip is applied TWICE**: before the blur passes
   (bounds math + alpha) and after the V pass (a big gaussian smears opaque
   pixels past the corner arcs — only a post-blur mask cuts that clean).
5. **ZStack paint order matters.** The opaque `Color.black` backing is the
   FIRST child. An opaque layer added later will black out everything
   (this bug has already happened once).
6. **`.compositingGroup()`** sits between the shader chain and the
   transforms so the shader's premultiplied alpha survives into
   `scaleEffect`/`rotation3DEffect`.
7. **`.transaction { $0.disablesAnimations = true }`** on the overlay view —
   the smoother owns all motion; SwiftUI implicit animation must never
   layer on top.
8. **Metal shader param order is positional.** `progressiveBlurV` takes:
   size, progress, maxRadius, edgeTilt, linkToBlur, linkMultiplier,
   gateDegrees, topSpanFrac, sideSpanFrac. Keep the call in
   `FadeOverlayView` in sync when touching either side.
9. **The dissolve must be exactly zero at rest** (`progress == 0`,
   `tilt == 0`). If you touch the dissolve math, verify the at-rest overlay
   is pixel-identical to the desktop.
10. **Dissolve spans must not collapse toward zero at low drive** — a
    razor-thin full-strength band renders as a hard box, not a gradient.
    The `mix(0.25, 1.0, growth)` floor is load-bearing.

## Conventions

- Comments in the shaders and view explain WHY (often "this exact value was
  chosen after a visible bug"). If you change behavior a comment describes,
  update the comment or delete it honestly — stale why-comments are worse
  than none.
- No animation APIs anywhere in the render path. Lerp only.
- Sliders are cheap; new tunables go on the smoother/state machine as
  `@Published`, get a slider, and ship with a sane default. The user will
  ask for the slider eventually anyway.

## Build / verify

```
xcodebuild -project LidFade.xcodeproj -scheme LidFade -configuration Debug build
```

Grep the output for `error|BUILD`. There is no test target; correctness is
verified by building and by the user physically closing their laptop.

## Known fakery

- Display corner radius is hardcoded 10pt (no public API).
- `minOpenAngleToArm`, hysteresis values, etc. are empirical, not derived.
- The screenshot is captured once at trigger time (async ScreenCaptureKit);
  `beginOverlay` re-checks `stateMachine.phase` when it lands in case the
  lid was released before capture completed.

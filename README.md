# <center>LidFade</center>

Your lid closes. The screen becomes the lid.

LidFade watches the physical lid-angle sensor on supported MacBooks and,
the instant you start closing the lid, freezes the screen with a screenshot
and folds it away like — well, like a lid: progressive gaussian melt, a
stretch from the hinge, and a 3D tilt driven by the *actual angle of the
actual hinge*. Release mid-close and it glides back, so simple adjustment doesn't block your workflow. Smoothly animated to avoid any weird, icky jitters.

Inspired by Apple's **iPhone Duo** — the first foldable iPhone, announced
September 2026 — whose screen blends seamlessly across its hinge as the
device opens and closes. LidFade borrows that feeling for the one hinge
MacBooks have always had: your display doesn't just turn off when you close
the lid, it *folds*.

No animation curves. No fake easings. Every pixel is a pure function of the
hardware's lid angle.

## The Duo illusion

This is a parlour trick, and it's basically playing your eyes.

When a lid physically closes, two things change at once — the screen turns
away from you, *and* your viewing angle of it deforms: the surface
foreshortens, the far edge recedes, the picture you perceive compresses. LidFade recreates The
iPhone Duo effect: it captures the screen exactly as it was, then **counter-acts the
closing**. The blur swallows the top as it recedes, the image stretches from
the hinge to compensate for the foreshortening, and the whole thing tilts
by precisely the angle the lid has moved — working against your changing
perspective so the perceived screen stays put, right up until the physical
lid wins and reality takes over.

Done right, your brain never registers a screen moving at all — just the
world politely dimming to black. Done wrong, it looks like the screen is
falling over. The difference between those two outcomes is *your eyes*, and
here's the catch:

> **The illusion is viewing-angle dependent.** Sitting close? Far? Off to
> the side? Lid raised on a stand? The same settings will read differently
> from every position, because your perception of the physical lid is what
> this app is fighting. There is no universally correct configuration —
> only the one that fools *your* eyes from *your* chair.

Which is exactly why everything is a slider.

> **Healthy reminder: your MacBook's hinges can break if you're not careful.** Customize your sliders and test gently in moderation.

No animation curves. No fake easings. Every pixel is a pure function of the
hardware's lid angle.

## The effect stack

The overlay is a screenshot composited in four layers, top of the fold down:

1. **Progressive blur** — a separable two-pass gaussian (`ProgressiveBlur.metal`,
   17 taps per axis) whose radius ramps from 0 at the hinge to `maxBlurRadius`
   at the top, driven by close progress. The top of your screen dissolves
   into fog first, because that's the part that moves first.
2. **Dim** — folded *into* the vertical blur pass itself: the shader mixes
   toward black with the same progress driver. One less layer.
3. **Edge dissolve** — the transformed quad's top/left/right boundaries melt
   into the black backing with premultiplied alpha instead of terminating as
   a hard line. Two drivers, switchable:
   - **Linked** (default): the dissolve rides the blur's own curve, scaled by
     a multiplier — more blur, more melt, in lockstep.
   - **Unlinked**: the dissolve runs on its own tilt gate + growth sliders.
4. **Geometry** — vertical stretch anchored at the hinge, then a
   `rotation3DEffect` by the real lid delta about the bottom edge. The screen
   tips away exactly as far as your lid has.


## The pipeline

```
LidAngleSensor (IOKit HID, 60 Hz poll)
  → LidStateMachine (stationary-point arming, hysteresis, stall-cancel)
    → OverlayMotionSmoother (60 Hz lerp + ease-in power curves)
      → FadeOverlayModel → FadeOverlayView (Metal via .layerEffect)
```

- **LidAngleSensor** polls the anonymous HID usage page that Apple doesn't
  document and the notch made famous.
- **LidStateMachine** turns raw angles into intent: hold still ~0.6s to arm
  an anchor, cross `closeHysteresis` while trending down to start, and a
  *stall* mid-close (stationary below `closeCancelProgress`) cancels, glides
  the overlay back to zero, and re-arms where you stopped.
- **OverlayMotionSmoother** is the only place time exists — a 60 Hz lerp
  chasing targets set by the state machine, with independent ease-in
  exponents for tilt and stretch. Lerp, not animation: releases glide, snaps
  don't exist.
- **FadeOverlayView** renders everything; `maxSampleOffset` is deliberately
  `.zero` (padded intermediate textures leak ghost extensions into the
  output — see comments in the file for that whole saga).

## Tuning

Because the illusion depends on your eyes, your seat, and your machine,
**literally everything is adjustable — on purpose, not as a feature
checklist**. The app window is a live mixing desk covering every layer of
the trick:

- **State machine** — arming tolerance/window, close & reopen hysteresis,
  and the stall-cancel threshold (how far you can push the lid before
  letting go still counts as "cancel" instead of "commit").
- **Motion** — lerp factor (snappy ↔ floaty), independent ease-in exponents
  for tilt and stretch, and how far the stretch goes.
- **The blur** — top blur power (max radius), so you can dial from a whisper
  of fog to full-on melted wax.
- **The dissolve** — link it to the blur's curve (with a sync multiplier) or
  let it run on its own tilt gate and depth sliders.

Every slider reshapes the effect *mid-animation* — drag one while the lid
is closing and watch the physics of your illusion change in real time. Find
the numbers that make your particular eyeballs believe it, and they stick.

## Requirements

- MacBook with a readable lid-angle sensor (this app reads a private HID so it may change depending on your machine)
- macOS with ScreenCaptureKit
- Screen Recording permission (requested on launch)
- Xcode 26+ / Swift 6.3 to build

## Build

```
xcodebuild -project LidFade.xcodeproj -scheme LidFade -configuration Debug build
```

## Honest limitations

- The corner radius is a hardcoded 10pt because Apple publishes the lid
  angle but not the corner radius.
- The screenshot is captured once at trigger time — the overlay shows the
  world as it was when you started closing. Which is rather the point.
- This means the shader is **not live**. You can implement a screenrecording feature yourself.
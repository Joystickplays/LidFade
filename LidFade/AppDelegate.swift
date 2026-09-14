import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let sensor = LidAngleSensor()
    let stateMachine = LidStateMachine()
    let motion = OverlayMotionSmoother()
    private lazy var overlay = OverlayWindowController(smoother: motion)
    private var cancellables = Set<AnyCancellable>()

    /// True once a screenshot has been captured and the overlay window exists —
    /// stays true through a cancel-and-glide-back-to-zero, only clearing once the
    /// motion smoother has actually settled at 0 and the window is torn down.
    /// This is what lets a second close, started while the first is still fading
    /// out, just retarget the same window instead of re-capturing.
    private var overlayPresented = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestScreenRecordingPermissionIfNeeded()

        stateMachine.attach(to: sensor)
        sensor.start()
        motion.start()

        stateMachine.$phase
            .sink { [weak self] phase in self?.handlePhaseChange(phase) }
            .store(in: &cancellables)

        motion.$progress
            .combineLatest(motion.$tiltDegrees, motion.$stretchScale)
            .sink { [weak self] progress, tilt, stretch in self?.handleMotionUpdate(progress: progress, tilt: tilt, stretch: stretch) }
            .store(in: &cancellables)

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(handleWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// The only place raw, degree-driven targets are set. Everything downstream
    /// (what's actually rendered) is the smoother chasing these.
    private func handlePhaseChange(_ phase: LidPhase) {
        switch phase {
        case .closing(let anchor, let progress):
            motion.targetProgress = progress
            motion.targetTiltDegrees = anchor - stateMachine.currentAngle
            if !overlayPresented {
                overlayPresented = true
                beginOverlay()
            }
        case .armed, .idle:
            // Don't tear the window down here — just retarget to zero and let
            // handleMotionUpdate dismiss it once the glide actually settles.
            // That's what makes releasing the lid cancel smoothly instead of
            // snapping the overlay away.
            motion.targetProgress = 0
            motion.targetTiltDegrees = 0
        }
    }

    private func handleMotionUpdate(progress: Double, tilt: Double, stretch: Double) {
        overlay.update(progress: progress, tiltDegrees: tilt, stretchScale: stretch)

        let settledAtZero = motion.targetProgress == 0 && progress < 0.001 && abs(tilt) < 0.05 && abs(stretch - 1.0) < 0.005
        if overlayPresented, settledAtZero {
            overlay.dismiss()
            overlayPresented = false
        }
    }

    /// Captures the current screen the instant closing is first detected. Since
    /// ScreenCaptureKit's capture is async, the lid could theoretically be
    /// released again before it lands — the guard below checks we're still
    /// actually closing before showing anything.
    private func beginOverlay() {
        guard let displayID = ScreenGrabber.builtinDisplayID() else {
            overlayPresented = false
            return
        }
        Task {
            guard let image = await ScreenGrabber.captureBuiltinDisplay(displayID: displayID) else {
                overlayPresented = false
                return
            }
            guard case .closing = stateMachine.phase else {
                overlayPresented = false
                return
            }
            overlay.present(image: image, on: displayID)
        }
    }

    private func requestScreenRecordingPermissionIfNeeded() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    @objc private func handleWillSleep() {
        overlay.dismiss()
        overlayPresented = false
    }

    @objc private func handleDidWake() {
        stateMachine.resetAfterSleepOrWake()
        motion.targetProgress = 0
        motion.targetTiltDegrees = 0
    }
}

import AppKit
import SwiftUI
import Combine

final class FadeOverlayModel: ObservableObject {
    @Published var image: CGImage?
    @Published var progress: Double = 0
    @Published var tiltDegrees: Double = 0
    @Published var stretchScale: Double = 1.0
}

final class OverlayWindowController {
    private var window: NSWindow?
    private let model = FadeOverlayModel()
    private let smoother: OverlayMotionSmoother

    init(smoother: OverlayMotionSmoother) {
        self.smoother = smoother
    }

    func present(image: CGImage, on displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: { matches($0, displayID) }) ?? NSScreen.main else { return }

        model.image = image
        model.progress = 0
        model.tiltDegrees = 0
        model.stretchScale = 1.0

        let win = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Suppress macOS's default show/order-in animation (the "pop with a
        // slight scale" effect) — we're driving every value ourselves.
        win.animationBehavior = .none

        let hv = NSHostingView(rootView: FadeOverlayView(model: model, tuning: smoother))
        hv.wantsLayer = true
        // Belt-and-suspenders: kill implicit Core Animation actions on the
        // backing layer too, since the rotation/blur touch layer properties
        // every frame and we don't want CA smoothing those on its own.
        hv.layer?.actions = [
            "transform": NSNull(),
            "position": NSNull(),
            "bounds": NSNull(),
            "opacity": NSNull(),
            "contents": NSNull(),
            "sublayers": NSNull(),
            "hidden": NSNull()
        ]
        win.contentView = hv
        win.orderFrontRegardless()

        window = win
    }

    /// Called every smoothed tick while a close (or its cancel) is in flight.
    func update(progress: Double, tiltDegrees: Double, stretchScale: Double) {
        model.progress = progress
        model.tiltDegrees = tiltDegrees
        model.stretchScale = stretchScale
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
        model.image = nil
        model.progress = 0
        model.tiltDegrees = 0
        model.stretchScale = 1.0
    }

    private func matches(_ screen: NSScreen, _ displayID: CGDirectDisplayID) -> Bool {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDirectDisplayID(num.uint32Value) == displayID
    }
}

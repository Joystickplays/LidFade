import CoreGraphics
import ScreenCaptureKit

/// Captures the built-in display only — the lid angle only ever relates to that
/// screen, so an external monitor in clamshell mode should never fade.
///
/// `CGDisplayCreateImage` (the old synchronous capture API) has been removed from
/// the SDK — Apple now requires ScreenCaptureKit for all screen capture, which is
/// asynchronous. This still runs at the instant closing is detected; it just hands
/// the image back via `await` instead of a direct return value.
enum ScreenGrabber {
    static func builtinDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? displays.first
    }

    static func captureBuiltinDisplay(displayID: CGDirectDisplayID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                print("[ScreenGrabber] built-in display not found in SCShareableContent")
                return nil
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            print("[ScreenGrabber] capture failed: \(error)")
            return nil
        }
    }
}

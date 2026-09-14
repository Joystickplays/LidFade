import Foundation
import Combine
import IOKit.hid

/// Reads the physical lid-angle sensor — a Hall-effect rotary sensor (MagAlpha
/// MA781) on the SPU/AppleSPUHIDDriver bus — via the public IOHIDManager /
/// IOHIDDevice APIs.
///
/// This still relies on an undocumented HID usage (Sensor page 0x20, Orientation
/// usage 0x8A) and a feature-report layout Apple hasn't published, but unlike a
/// private-symbol approach it only calls stable, public IOKit.hid entry points.
///
/// Verified device identity: VendorID 0x05AC (Apple), ProductID 0x8104,
/// PrimaryUsagePage 0x20, PrimaryUsage 0x8A. Confirm on your own Mac with:
///   hidutil list --matching '{"VendorID":0x05AC,"ProductID":0x8104,"PrimaryUsagePage":32,"PrimaryUsage":138}'
/// and change `productID` below if yours differs.
///
/// Only Macs with the physical sensor (2019+ MacBook Pro/Air hinge sensor) expose
/// this device at all — on anything else, `isAvailable` just stays false.
final class LidAngleSensor: ObservableObject {
    @Published private(set) var angleDegrees: Double = -1
    @Published private(set) var isAvailable: Bool = false

    /// This is a feature report, not a streamed input report, so there's no push
    /// notification for it — polling is the only option. 60 Hz keeps the fade
    /// responsive without hammering the bus.
    var pollInterval: TimeInterval = 1.0 / 60.0

    private let vendorID = 0x05AC
    private var productID = 0x8104   // override if hidutil finds a different one on your Mac

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.lidfade.hidpoll")

    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            print("[LidAngleSensor] failed to open IOHIDManager")
            return
        }
        manager = mgr

        IOHIDManagerSetDeviceMatching(mgr, [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID,
            kIOHIDPrimaryUsagePageKey as String: 0x0020,
            kIOHIDPrimaryUsageKey as String: 0x008A,
        ] as CFDictionary)

        guard let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>, let dev = devices.first else {
            print("[LidAngleSensor] no matching lid-angle sensor device found — check productID with hidutil")
            return
        }

        guard IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            print("[LidAngleSensor] failed to open matched HID device")
            return
        }
        device = dev

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let dev = device {
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        if let mgr = manager {
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    private func poll() {
        guard let dev = device else { return }
        var buf = [UInt8](repeating: 0, count: 8)
        var len: CFIndex = buf.count
        let result = buf.withUnsafeMutableBytes {
            IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 1,
                $0.baseAddress!.assumingMemoryBound(to: UInt8.self), &len)
        }
        guard result == kIOReturnSuccess, len >= 3 else { return }
        let angle = Double(Int(buf[2]) << 8 | Int(buf[1]))

        DispatchQueue.main.async {
            self.angleDegrees = angle
            self.isAvailable = true
        }
    }
}

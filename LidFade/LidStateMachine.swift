import Foundation
import Combine

enum LidPhase: Equatable {
    case idle
    case armed(anchor: Double)
    case closing(anchor: Double, progress: Double)
}

/// Watches a stream of lid-angle samples and derives:
///  1. A "point" — an angle the lid has held stationary within a small tolerance.
///  2. A "closing" progress value, computed fresh from the current angle relative
///     to that point on every single sample. There is no timer and no animation
///     curve anywhere in this file — `progress` is a pure function of `angle`.
final class LidStateMachine: ObservableObject {
    // MARK: Tunable thresholds (safe to change live from the calibration UI)
    @Published var stationaryWindow: TimeInterval = 0.6      // how long it must hold still
    @Published var stationaryTolerance: Double = 0.5         // ± band that counts as "stationary"
    @Published var minOpenAngleToArm: Double = 12            // ignore near-closed "points"
    @Published var closeHysteresis: Double = 1.2             // degrees past anchor before "closing" fires
    @Published var reopenHysteresis: Double = 1.0            // degrees back before "closing" aborts
    /// A "closing" that goes stationary above this progress is treated as the
    /// user stopping mid-push (a cancel), not the lid actually reaching closed.
    @Published var closeCancelProgress: Double = 0.9

    @Published private(set) var phase: LidPhase = .idle
    @Published private(set) var currentAngle: Double = -1

    var onClosingStarted: (() -> Void)?
    var onClosingEnded: (() -> Void)?

    private var samples: [(t: Date, a: Double)] = []
    private var cancellable: AnyCancellable?

    func attach(to sensor: LidAngleSensor) {
        cancellable = sensor.$angleDegrees
            .filter { $0 >= 0 }
            .sink { [weak self] angle in self?.ingest(angle: angle) }
    }

    func resetAfterSleepOrWake() {
        samples.removeAll()
        phase = .idle
    }

    private func ingest(angle: Double) {
        currentAngle = angle
        let now = Date()
        samples.append((now, angle))
        samples.removeAll { now.timeIntervalSince($0.t) > stationaryWindow }

        switch phase {
        case .idle, .armed:
            updateStationaryPoint()
            checkForClosingStart(angle: angle)
        case .closing(let anchor, _):
            updateClosing(angle: angle, anchor: anchor)
        }
    }

    /// If every sample in the trailing window fits inside `stationaryTolerance`,
    /// returns the window's average as the stationary "point".
    private func stationaryPoint() -> Double? {
        guard let first = samples.first,
              Date().timeIntervalSince(first.t) >= stationaryWindow * 0.8,
              samples.count >= 3 else { return nil }

        let values = samples.map { $0.a }
        guard let lo = values.min(), let hi = values.max(), (hi - lo) <= stationaryTolerance else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func updateStationaryPoint() {
        guard let point = stationaryPoint(), point >= minOpenAngleToArm else { return }
        phase = .armed(anchor: point)
    }

    private func checkForClosingStart(angle: Double) {
        guard case .armed(let anchor) = phase else { return }
        guard angle <= anchor - closeHysteresis, isTrendingDown() else { return }
        phase = .closing(anchor: anchor, progress: progress(angle: angle, anchor: anchor))
        onClosingStarted?()
    }

    private func updateClosing(angle: Double, anchor: Double) {
        if angle >= anchor - reopenHysteresis {
            phase = .armed(anchor: anchor)
            onClosingEnded?()
            return
        }
        let p = progress(angle: angle, anchor: anchor)

        // Stall-cancel: the lid went stationary mid-close (and isn't nearly
        // shut) — the user stopped pushing. Fire the ended callback so the
        // overlay retargets to zero and glides back, and re-arm at the held
        // angle so pushing again re-triggers from right here.
        if p < closeCancelProgress, let point = stationaryPoint(), point >= minOpenAngleToArm {
            phase = .armed(anchor: point)
            onClosingEnded?()
            return
        }

        phase = .closing(anchor: anchor, progress: p)
    }

    /// Net direction over the last few samples — guards against arming on a single noisy reading.
    private func isTrendingDown() -> Bool {
        guard samples.count >= 3 else { return false }
        let recent = samples.suffix(min(5, samples.count)).map { $0.a }
        guard let first = recent.first, let last = recent.last else { return false }
        return (first - last) > 0.3
    }

    /// The only formula that drives the visual effect. 0 at the anchor, 1 at fully closed (0°).
    private func progress(angle: Double, anchor: Double) -> Double {
        guard anchor > 0 else { return 0 }
        return min(max((anchor - angle) / anchor, 0), 1)
    }
}

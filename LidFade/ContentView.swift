import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var sensor: LidAngleSensor
    @ObservedObject var stateMachine: LidStateMachine
    @ObservedObject var motion: OverlayMotionSmoother

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            Text("Lid angle").font(.headline)
            Text(sensor.isAvailable ? String(format: "%.2f°", sensor.angleDegrees) : "sensor unavailable")
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .foregroundStyle(sensor.isAvailable ? .primary : .secondary)

            Divider()
            phaseView
            Divider()

            Text("Tuning").font(.headline)
            slider("Stationary tolerance (°)", $stateMachine.stationaryTolerance, 0.1...2.0)
            slider("Stationary window (s)", $stateMachine.stationaryWindow, 0.2...2.0)
            slider("Close hysteresis (°)", $stateMachine.closeHysteresis, 0.2...4.0)
            slider("Reopen hysteresis (°)", $stateMachine.reopenHysteresis, 0.2...4.0)
            slider("Stall-cancel progress (1 = never)", $stateMachine.closeCancelProgress, 0.1...1.0)

            Divider()
            Text("Motion smoothing").font(.headline)
            slider("Lerp factor (snappy ↔ floaty)", $motion.lerpFactor, 0.05...0.6)
            slider("Tilt curve — ease-in (1 linear → 4 expo)", $motion.tiltExponent, 1.0...4.0)
            slider("Stretch curve — ease-in (1 linear → 4 expo)", $motion.stretchExponent, 1.0...4.0)
            slider("Stretch amount (taller at full close)", $motion.stretchAmount, 0.0...20.0    )
            slider("Top blur power (max radius px)", $motion.maxBlurRadius, 0.0...360.0)

            Divider()
            Text("Edge dissolve").font(.headline)
            Toggle("Link dissolve to blur curve", isOn: $motion.dissolveLinkedToBlur)
            slider("Link multiplier (blur ↔ dissolve sync)", $motion.dissolveLinkMultiplier, 0.1...3.0)
                .disabled(!motion.dissolveLinkedToBlur)
                .opacity(motion.dissolveLinkedToBlur ? 1 : 0.4)
            slider("Gate — tilt before edges vanish (°)", $motion.dissolveGateDegrees, 0.5...10.0)
                .disabled(motion.dissolveLinkedToBlur)
                .opacity(motion.dissolveLinkedToBlur ? 0.4 : 1)
            slider("Top dissolve depth (at full close)", $motion.dissolveTopSpan, 0.05...0.5)
            slider("Side dissolve depth (at full close)", $motion.dissolveSideSpan, 0.02...0.3)

            Text(String(format: "rendered progress %.2f · tilt %.2f° · stretch %.2f×", motion.progress, motion.tiltDegrees, motion.stretchScale))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 380)
    }

    @ViewBuilder
    private var phaseView: some View {
        switch stateMachine.phase {
        case .idle:
            Label("Idle — hold the lid still to set a point", systemImage: "circle.dotted")
        case .armed(let anchor):
            Label(String(format: "Armed at %.2f°", anchor), systemImage: "smallcircle.filled.circle")
        case .closing(let anchor, let progress):
            VStack(alignment: .leading, spacing: 6) {
                Label(String(format: "Closing from %.2f°", anchor), systemImage: "moon.fill")
                ProgressView(value: progress)
            }
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label): \(String(format: "%.2f", value.wrappedValue))").font(.caption)
            Slider(value: value, in: range)
        }
    }
}

import SwiftUI

@main
struct LidFadeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("LidFade") {
            ContentView(sensor: appDelegate.sensor, stateMachine: appDelegate.stateMachine, motion: appDelegate.motion)
                .frame(width: 380, height: 620)
        }
        .windowResizability(.contentSize)
    }
}

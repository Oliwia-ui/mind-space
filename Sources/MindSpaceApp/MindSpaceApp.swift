import AppKit
import MindSpaceCore
import SwiftUI

@main
struct MindSpaceApp: App {
    @NSApplicationDelegateAdaptor(MindSpaceApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(MindSpaceConfiguration.productName) {
            NativeFoundationView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
    }
}

private final class MindSpaceApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: false)
    }
}

private struct NativeFoundationView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.035, blue: 0.065), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(MindSpaceConfiguration.productName)
                    .font(.system(size: 42, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Text("Your thoughts, still in motion.")
                    .foregroundStyle(.white.opacity(0.55))
                Button("MAKE IT MAKE SENSE") {}
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.72, green: 0.30, blue: 0.13))
                    .accessibilityIdentifier("makeItMakeSenseButton")
            }
        }
        .accessibilityIdentifier("mindSpaceRoot")
    }
}

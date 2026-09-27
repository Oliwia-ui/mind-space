import AppKit
import MindSpaceCore
import SwiftUI

@main
struct MindSpaceApp: App {
    @NSApplicationDelegateAdaptor(MindSpaceApplicationDelegate.self) private var appDelegate
    private let model = MindSpaceAppModel()

    var body: some Scene {
        WindowGroup(MindSpaceConfiguration.productName) {
            MindSpaceRootView(model: model)
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
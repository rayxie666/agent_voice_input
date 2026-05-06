import AppKit
import SwiftUI

@main
struct VoiceInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(settings)
        } label: {
            Image(systemName: menuIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
                .environmentObject(settings)
        }
    }

    private var menuIcon: String {
        switch coordinator.state {
        case .idle:         return "mic"
        case .recording:    return "mic.fill"
        case .transcribing: return "waveform"
        case .polishing:    return "wand.and.stars"
        case .error:        return "exclamationmark.triangle"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Don't auto-prompt for Accessibility on launch — that creates a loop
        // after every "Quit & Reopen" the system asks the user to do. The
        // user-facing "打开授权页" button triggers the prompt only when asked.
    }
}

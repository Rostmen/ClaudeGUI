import AppKit
import SwiftUI
import GhosttyKit

// MARK: - GhosttyEmbedApp

/// Singleton that owns the Ghostty app state. Must be created on the main thread.
public class GhosttyEmbedApp {
    public static let shared = GhosttyEmbedApp()

    /// The underlying Ghostty app state.
    let ghosttyApp: Ghostty.App

    private init() {
        // ghostty_init() must be called before any other Ghostty API.
        // It sets up the global Zig allocator; without it ghostty_config_new crashes.
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        if result != GHOSTTY_SUCCESS {
            Ghostty.logger.critical("ghostty_init failed: \(result)")
        }

        // Write a thin config override so Ghostty's background matches Tenvy's
        // glass UI (semi-transparent black, same as SwiftTerm's kWindowOpacity).
        // We chain the user's existing Ghostty config first so their other
        // settings (font, keybindings, etc.) are still respected.
        let userConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ghostty/config").path
        var lines = [
            "background = #000000",
            "background-opacity = 0.5",
        ]
        if FileManager.default.fileExists(atPath: userConfig) {
            lines.insert("config-file = \(userConfig)", at: 0)
        }
        let configPath = Self.configPath
        try? lines.joined(separator: "\n").write(toFile: configPath, atomically: true, encoding: .utf8)

        ghosttyApp = Ghostty.App(configPath: configPath)
    }

    private static let configPath = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("tenvy-ghostty.conf")

    /// Rewrites the Ghostty config for the given appearance and reloads it.
    /// Safe to call on appearance changes; existing surfaces pick up the new colors.
    @MainActor
    public func applyAppearance(isDark: Bool) {
        let userConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ghostty/config").path
        var lines = isDark
            ? ["background = #000000", "background-opacity = 0.5"]
            : ["background = #ffffff", "background-opacity = 0.55",
               "foreground = #1a1a1a"]
        if FileManager.default.fileExists(atPath: userConfig) {
            lines.insert("config-file = \(userConfig)", at: 0)
        }
        try? lines.joined(separator: "\n")
            .write(toFile: Self.configPath, atomically: true, encoding: .utf8)
        ghosttyApp.reloadConfig()
    }
}

// MARK: - GhosttyEmbedSurface

/// A handle to a running Ghostty surface. Retain this to keep the surface alive.
public class GhosttyEmbedSurface {
    let surfaceView: Ghostty.SurfaceView

    init(surfaceView: Ghostty.SurfaceView) {
        self.surfaceView = surfaceView
    }

    /// Send text directly to the terminal (bypasses keyboard encoding).
    @MainActor
    public func sendText(_ text: String) {
        surfaceView.surfaceModel?.sendText(text)
    }

    /// The underlying NSView for embedding in AppKit/SwiftUI.
    public var nsView: NSView { surfaceView }

    /// Notify Ghostty that the visible area has changed size.
    /// Must be called whenever the host view's bounds change.
    public func notifyResize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        surfaceView.sizeDidChange(size)
    }
}

// MARK: - Surface Factory

extension GhosttyEmbedApp {
    /// Create a new terminal surface running the given command.
    /// - Parameters:
    ///   - command: Full command string passed to Ghostty (e.g., "/usr/bin/claude --resume ID").
    ///   - workingDirectory: Initial working directory for the terminal.
    ///   - environment: Extra environment variables injected into the session.
    @MainActor
    public func makeSurface(
        command: String,
        workingDirectory: String,
        environment: [String: String] = [:]
    ) -> GhosttyEmbedSurface? {
        guard let appHandle = ghosttyApp.app else { return nil }

        var config = Ghostty.SurfaceConfiguration()
        config.command = command
        config.workingDirectory = workingDirectory
        config.environmentVariables = environment

        let view = Ghostty.SurfaceView(appHandle, baseConfig: config)
        return GhosttyEmbedSurface(surfaceView: view)
    }
}

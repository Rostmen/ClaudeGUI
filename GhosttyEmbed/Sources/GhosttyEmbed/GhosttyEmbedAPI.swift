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
        ghosttyApp = Ghostty.App()
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

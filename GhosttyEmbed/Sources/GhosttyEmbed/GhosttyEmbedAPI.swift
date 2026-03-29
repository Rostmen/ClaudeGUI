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

// MARK: - Split Direction

/// The direction in which a new split pane should be created.
public enum GhosttyEmbedSplitDirection {
  case right   // new pane to the right (horizontal split, new on right)
  case down    // new pane below (vertical split, new on bottom)
  case left    // new pane to the left (horizontal split, new on left)
  case up      // new pane above (vertical split, new on top)
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

    /// Make this surface the keyboard focus, ensuring Ghostty's internal state is
    /// correctly updated even when the surface was created with the default `focused = true`.
    ///
    /// Ghostty's `SurfaceView` starts with `focused = true` by default.  If
    /// `becomeFirstResponder()` is called without first resetting that flag, the
    /// guard inside `focusDidChange(_:)` short-circuits and the C layer's
    /// `ghostty_surface_set_focus` is never called — so Ghostty internally still
    /// considers the old surface focused for operations like paste.
    ///
    /// Calling `resignFirstResponder()` first resets `focused` to `false`
    /// (Ghostty itself does this in SplitView), so the subsequent
    /// `makeFirstResponder` properly triggers the full focus handshake.
    @MainActor
    public func makeFocused() {
        // Reset focus state (no-op if already false; safe to call even when not first responder).
        _ = surfaceView.resignFirstResponder()
        surfaceView.window?.makeFirstResponder(surfaceView)
    }

    /// The PID of the foreground process currently running in this terminal's PTY.
    /// Returns 0 if the surface is not yet ready.
    /// Uses `ghostty_surface_foreground_pid` from the Ghostty C API (added in PR #11922).
    @MainActor
    public var foregroundPid: pid_t {
        guard let surface = surfaceView.surface else { return 0 }
        let pid64 = ghostty_surface_foreground_pid(surface)
        return pid_t(pid64)
    }

    /// Notify Ghostty that the visible area has changed size.
    /// Must be called whenever the host view's bounds change.
    public func notifyResize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        surfaceView.sizeDidChange(size)
    }

    /// Subscribe to split requests from Ghostty's context menu for this surface.
    /// Returns an opaque token — the caller must retain it and pass it to
    /// `NotificationCenter.default.removeObserver(_:)` when done.
    @MainActor
    public func onSplitRequest(_ handler: @escaping (GhosttyEmbedSplitDirection) -> Void) -> NSObjectProtocol {
        let sv = surfaceView
        return NotificationCenter.default.addObserver(
            forName: Notification.Name("com.mitchellh.ghostty.newSplit"),
            object: sv,
            queue: .main
        ) { notification in
            // C enum structs may bridge to NSNumber when crossing the Any barrier.
            // Try direct cast first, then fall back to reading the raw integer.
            let rawValue: UInt32
            if let d = notification.userInfo?["direction"] as? ghostty_action_split_direction_e {
                rawValue = d.rawValue
            } else if let n = notification.userInfo?["direction"] as? NSNumber {
                rawValue = n.uint32Value
            } else {
                rawValue = GHOSTTY_SPLIT_DIRECTION_RIGHT.rawValue
            }
            let direction: GhosttyEmbedSplitDirection
            switch rawValue {
            case GHOSTTY_SPLIT_DIRECTION_RIGHT.rawValue: direction = .right
            case GHOSTTY_SPLIT_DIRECTION_DOWN.rawValue:  direction = .down
            case GHOSTTY_SPLIT_DIRECTION_LEFT.rawValue:  direction = .left
            case GHOSTTY_SPLIT_DIRECTION_UP.rawValue:    direction = .up
            default:                                      direction = .right
            }
            handler(direction)
        }
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

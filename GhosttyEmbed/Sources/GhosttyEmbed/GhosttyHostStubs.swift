import AppKit
import SwiftUI
import os
import GhosttyKit

// MARK: - AppDelegate Stub
//
// Satisfies the compiler for Ghostty code that casts `NSApplication.shared.delegate as? AppDelegate`.
// At runtime the cast FAILS (Tenvy's actual AppDelegate is a different class in a different module),
// so all blocks guarded by `if let appDelegate = ... as? AppDelegate` are safely skipped.
// Static members like `AppDelegate.logger` are used directly by compiled Ghostty code and must exist.
class AppDelegate: NSObject {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.tenvy",
        category: "ghostty"
    )

    struct GhosttyContainer {
        var config: Ghostty.Config { Ghostty.Config(config: nil) }
        var app: ghostty_app_t? { nil }
    }

    var ghostty: GhosttyContainer { GhosttyContainer() }
    var undoManager: UndoManager? { nil }

    func checkForUpdates(_ sender: Any?) {}
    func closeAllWindows(_ sender: Any?) {}
    func toggleVisibility(_ sender: Any?) {}
    func toggleQuickTerminal(_ sender: Any?) {}
    func syncFloatOnTopMenu(_ window: TerminalWindow) {}
    func setSecureInput(_ mode: Ghostty.SetSecureInput) {}
    func performGhosttyBindingMenuKeyEquivalent(with event: NSEvent) -> Bool { false }
}

// MARK: - BaseTerminalController Stub
//
// Satisfies the compiler for Ghostty code that casts `windowController as? BaseTerminalController`.
// Tenvy's window controllers do not extend this class, so all such casts return nil at runtime.
class BaseTerminalController: NSWindowController {
    @objc func changeTabTitle(_ sender: Any?) {}
    var commandPaletteIsShowing: Bool { false }
    var focusFollowsMouse: Bool { false }
    var focusedSurface: Ghostty.SurfaceView? { nil }
    var titleOverride: String? = nil
    var surfaceTree: SplitTree<Ghostty.SurfaceView> { SplitTree<Ghostty.SurfaceView>() }

    func promptTabTitle() {}
    func toggleBackgroundOpacity() {}
}

// MARK: - TerminalWindow Stub
//
// Used by Ghostty.App.swift for float-on-top actions and Fullscreen.swift.
// Cast always fails at runtime in Tenvy since Tenvy's windows don't subclass TerminalWindow.
class TerminalWindow: NSWindow {
    func isTabBar(_ controller: NSTitlebarAccessoryViewController) -> Bool { false }
}
class HiddenTitlebarTerminalWindow: NSWindow {}

// MARK: - TerminalRestoreError Stub
//
// Used in SurfaceView_AppKit.swift's Codable conformance for window state restoration.
// Tenvy doesn't use NSWindowRestoration with Ghostty surfaces.
enum TerminalRestoreError: Error {
    case delegateInvalid
    case surfaceCreateFailed
}

// MARK: - SplitTree Stub
//
// Ghostty's split-pane data structure. We provide a minimal stub so split-related
// action handlers compile. These handlers are guarded by `controller.surfaceTree.isSplit`
// which returns false, so they are never executed at runtime.
struct SplitTree<T: AnyObject> {
    enum FocusDirection {
        case previous, next, up, down, left, right
    }

    final class Node {
        func node(view: T) -> Node? { nil }
    }

    var isSplit: Bool { false }
    var root: Node? { nil }

    func focusTarget(for direction: FocusDirection, from node: Node) -> Node? { nil }
}

// MARK: - SplitFocusDirection → SplitTree.FocusDirection
extension Ghostty.SplitFocusDirection {
    func toSplitTreeFocusDirection() -> SplitTree<Ghostty.SurfaceView>.FocusDirection {
        switch self {
        case .previous: return .previous
        case .next:     return .next
        case .up:       return .up
        case .down:     return .down
        case .left:     return .left
        case .right:    return .right
        }
    }
}

// MARK: - SecureInputOverlay Stub
//
// SwiftUI view shown when secure input is active. Not needed for embedded terminal.
struct SecureInputOverlay: View {
    var body: some View { EmptyView() }
}

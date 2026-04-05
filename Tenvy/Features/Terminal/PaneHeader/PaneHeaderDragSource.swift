import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Pasteboard Type

extension UTType {
  /// Pasteboard format for dragging pane IDs between split panes.
  static let tenvyPaneId = UTType(exportedAs: "com.tenvy.paneId")
}

extension NSPasteboard.PasteboardType {
  /// Pasteboard type for dragging pane terminal IDs.
  static let tenvyPaneId = NSPasteboard.PasteboardType(UTType.tenvyPaneId.identifier)
}

// MARK: - PaneHeaderDragSourceView (NSViewRepresentable)

/// SwiftUI wrapper for the AppKit drag source that covers the entire header.
struct PaneHeaderDragSourceView: NSViewRepresentable {
  let tenvySessionId: String
  let snapshotProvider: () -> NSImage?
  var hasIDEButton: Bool = false

  func makeNSView(context: Context) -> PaneHeaderDragSourceNSView {
    let view = PaneHeaderDragSourceNSView()
    view.tenvySessionId = tenvySessionId
    view.snapshotProvider = snapshotProvider
    view.hasIDEButton = hasIDEButton
    return view
  }

  func updateNSView(_ nsView: PaneHeaderDragSourceNSView, context: Context) {
    nsView.tenvySessionId = tenvySessionId
    nsView.snapshotProvider = snapshotProvider
    let changed = nsView.hasIDEButton != hasIDEButton
    nsView.hasIDEButton = hasIDEButton
    if changed {
      nsView.window?.invalidateCursorRects(for: nsView)
    }
  }
}

// MARK: - PaneHeaderDragSourceNSView

/// AppKit view that handles drag initiation for pane rearrangement.
///
/// Follows the same pattern as Ghostty's `SurfaceDragSourceView`:
/// - `mouseDragged` initiates `NSDraggingSession` with a 20%-scaled terminal snapshot
/// - `draggingSession(_:endedAt:)` detects drops outside windows for future cross-window support
/// - Escape key cancels the drag
final class PaneHeaderDragSourceNSView: NSView, NSDraggingSource {
  private static let previewScale: CGFloat = 0.2

  var tenvySessionId: String = ""
  var snapshotProvider: (() -> NSImage?)?
  var hasIDEButton: Bool = false

  private var isTracking: Bool = false
  private var escapeMonitor: Any?
  private var dragCancelledByEscape: Bool = false

  deinit {
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
    }
  }

  /// Width of the trailing button region where drag source passes through.
  /// Expands when the IDE button is present next to the close button.
  private static let closeButtonInset: CGFloat = 34
  private static let ideButtonExtraInset: CGFloat = 36

  private var trailingInset: CGFloat {
    hasIDEButton ? Self.closeButtonInset + Self.ideButtonExtraInset : Self.closeButtonInset
  }

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Pass through clicks in the trailing button region so SwiftUI handles them
    let localPoint = convert(point, from: superview)
    if localPoint.x > bounds.width - trailingInset {
      return nil
    }
    return super.hitTest(point)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    // Consume to prevent window dragging — drag starts in mouseDragged.
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    // Only track the draggable area (exclude trailing buttons)
    let dragRect = NSRect(x: 0, y: 0, width: max(0, bounds.width - trailingInset), height: bounds.height)
    addTrackingArea(NSTrackingArea(
      rect: dragRect,
      options: [.mouseEnteredAndExited, .activeInActiveApp],
      owner: self,
      userInfo: nil
    ))
  }

  override func resetCursorRects() {
    // Only set hand cursor in the draggable area
    let dragRect = NSRect(x: 0, y: 0, width: max(0, bounds.width - trailingInset), height: bounds.height)
    addCursorRect(dragRect, cursor: isTracking ? .closedHand : .openHand)
  }

  override func mouseDragged(with event: NSEvent) {
    guard !isTracking else { return }

    // Write tenvySessionId to pasteboard
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(tenvySessionId, forType: .tenvyPaneId)

    let item = NSDraggingItem(pasteboardWriter: pasteboardItem)

    // Create scaled preview from terminal snapshot
    if let snapshot = snapshotProvider?() {
      let imageSize = NSSize(
        width: snapshot.size.width * Self.previewScale,
        height: snapshot.size.height * Self.previewScale
      )
      let scaledImage = NSImage(size: imageSize)
      scaledImage.lockFocus()
      snapshot.draw(
        in: NSRect(origin: .zero, size: imageSize),
        from: NSRect(origin: .zero, size: snapshot.size),
        operation: .copy,
        fraction: 1.0
      )
      scaledImage.unlockFocus()

      let mouseLocation = convert(event.locationInWindow, from: nil)
      let origin = NSPoint(
        x: mouseLocation.x - imageSize.width / 2,
        y: mouseLocation.y - imageSize.height / 2
      )
      item.setDraggingFrame(
        NSRect(origin: origin, size: imageSize),
        contents: scaledImage
      )
    }

    let session = beginDraggingSession(with: [item], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = false
  }

  // MARK: NSDraggingSource

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .withinApplication ? .move : []
  }

  func draggingSession(
    _ session: NSDraggingSession,
    willBeginAt screenPoint: NSPoint
  ) {
    isTracking = true
    dragCancelledByEscape = false
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 { // Escape
        self?.dragCancelledByEscape = true
      }
      return event
    }
  }

  func draggingSession(
    _ session: NSDraggingSession,
    movedTo screenPoint: NSPoint
  ) {
    NSCursor.closedHand.set()
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
      self.escapeMonitor = nil
    }

    if operation == [] && !dragCancelledByEscape {
      let endsInWindow = NSApplication.shared.windows.contains { window in
        window.isVisible && window.frame.contains(screenPoint)
      }
      if !endsInWindow {
        NotificationCenter.default.post(
          name: .paneDragEndedNoTarget,
          object: nil,
          userInfo: [
            Notification.paneDragTenvySessionIdKey: tenvySessionId,
            Notification.paneDragEndedPointKey: screenPoint,
          ]
        )
      }
    }

    isTracking = false
  }
}

// MARK: - Notifications

extension Notification.Name {
  /// Posted when a pane drag ends outside any window (for future cross-window support).
  static let paneDragEndedNoTarget = Notification.Name("com.tenvy.paneDragEndedNoTarget")
}

extension Notification {
  static let paneDragTenvySessionIdKey = "tenvySessionId"
  static let paneDragEndedPointKey = "endedAtPoint"
}

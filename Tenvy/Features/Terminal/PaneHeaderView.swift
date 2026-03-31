// MIT License
//
// Copyright (c) 2026 Rostyslav Kobizsky
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

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

// MARK: - PaneHeaderAction

enum PaneHeaderAction {
  /// User clicked the close button.
  case closeRequested
}

// MARK: - PaneHeaderView

/// Header bar shown at the top of each terminal pane.
///
/// Displays the session/terminal title on the left and a close button on the right.
/// The entire header is draggable — initiating an AppKit drag session with the
/// pane's `terminalId` on the pasteboard for drop-to-split rearrangement.
struct PaneHeaderView: View {
  let title: String
  let terminalId: String
  var isSelected: Bool = false
  var isFileDropTarget: Bool = false
  var runtimeInfo: SessionRuntimeInfo?
  var isActive: Bool = false
  let snapshotProvider: () -> NSImage?
  let onAction: (PaneHeaderAction) -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var isBlinking = false
  @State private var dropHighlightPulse = false

  private var statusColor: Color {
    if isActive, let hookState = runtimeInfo?.hookState {
      return hookState.statusColor
    }
    return isActive ? .green : .gray
  }

  private var shouldBlink: Bool {
    isActive && (runtimeInfo?.hookState == .waiting || runtimeInfo?.hookState == .waitingPermission)
  }

  private var backgroundColor: Color {
    if isFileDropTarget {
      return colorScheme == .dark
        ? Color.accentColor.opacity(dropHighlightPulse ? 0.35 : 0.2)
        : Color.accentColor.opacity(dropHighlightPulse ? 0.3 : 0.15)
    }
    if isSelected {
      return colorScheme == .dark
        ? Color(red: 41/255, green: 42/255, blue: 47/255)
        : Color(red: 220/255, green: 222/255, blue: 228/255)
    }
    return colorScheme == .dark
      ? Color(nsColor: NSColor(white: 0.1, alpha: 1.0))
      : Color(nsColor: NSColor(white: 0.92, alpha: 1.0))
  }

  private var borderColor: Color {
    if isFileDropTarget {
      return Color.accentColor.opacity(0.5)
    }
    return colorScheme == .dark
      ? Color(nsColor: NSColor(white: 0.2, alpha: 1.0))
      : Color(nsColor: NSColor(white: 0.78, alpha: 1.0))
  }

  var body: some View {
    ZStack {
      // Drag source covers the full header
      PaneHeaderDragSourceView(
        terminalId: terminalId,
        snapshotProvider: snapshotProvider
      )

      HStack(spacing: 8) {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
          .opacity(shouldBlink ? (isBlinking ? 0.3 : 1.0) : 1.0)
          .animation(shouldBlink ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: isBlinking)
          .allowsHitTesting(false)

        Text(title)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(.secondary)
          .allowsHitTesting(false)

        Spacer()

        CloseButton {
          onAction(.closeRequested)
        }
      }
      .padding(.horizontal, 12)
    }
    .frame(height: 30)
    .background(backgroundColor)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(borderColor)
        .frame(height: 1)
    }
    .onChange(of: shouldBlink) { _, newValue in
      isBlinking = newValue
    }
    .onChange(of: isFileDropTarget) { _, targeted in
      if targeted {
        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
          dropHighlightPulse = true
        }
      } else {
        withAnimation(.easeOut(duration: 0.2)) {
          dropHighlightPulse = false
        }
      }
    }
    .animation(.easeInOut(duration: 0.15), value: isFileDropTarget)
    .onAppear {
      if shouldBlink { isBlinking = true }
    }
  }
}

// MARK: - CloseButton

/// Close button with hover highlight for the pane header.
private struct CloseButton: View {
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(isHovering ? .secondary : .tertiary)
        .frame(width: 20, height: 20)
        .background(isHovering ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }
}

// MARK: - PaneHeaderDragSourceView (NSViewRepresentable)

/// SwiftUI wrapper for the AppKit drag source that covers the entire header.
private struct PaneHeaderDragSourceView: NSViewRepresentable {
  let terminalId: String
  let snapshotProvider: () -> NSImage?

  func makeNSView(context: Context) -> PaneHeaderDragSourceNSView {
    let view = PaneHeaderDragSourceNSView()
    view.terminalId = terminalId
    view.snapshotProvider = snapshotProvider
    return view
  }

  func updateNSView(_ nsView: PaneHeaderDragSourceNSView, context: Context) {
    nsView.terminalId = terminalId
    nsView.snapshotProvider = snapshotProvider
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

  var terminalId: String = ""
  var snapshotProvider: (() -> NSImage?)?

  private var isTracking: Bool = false
  private var escapeMonitor: Any?
  private var dragCancelledByEscape: Bool = false

  deinit {
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
    }
  }

  /// Width of the trailing close button region where drag source passes through.
  private static let closeButtonInset: CGFloat = 34

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Pass through clicks in the close button region so SwiftUI handles them
    let localPoint = convert(point, from: superview)
    if localPoint.x > bounds.width - Self.closeButtonInset {
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
    // Only track the draggable area (exclude close button)
    let dragRect = NSRect(x: 0, y: 0, width: max(0, bounds.width - Self.closeButtonInset), height: bounds.height)
    addTrackingArea(NSTrackingArea(
      rect: dragRect,
      options: [.mouseEnteredAndExited, .activeInActiveApp],
      owner: self,
      userInfo: nil
    ))
  }

  override func resetCursorRects() {
    // Only set hand cursor in the draggable area
    let dragRect = NSRect(x: 0, y: 0, width: max(0, bounds.width - Self.closeButtonInset), height: bounds.height)
    addCursorRect(dragRect, cursor: isTracking ? .closedHand : .openHand)
  }

  override func mouseDragged(with event: NSEvent) {
    guard !isTracking else { return }

    // Write terminalId to pasteboard
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(terminalId, forType: .tenvyPaneId)

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
            Notification.paneDragTerminalIdKey: terminalId,
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
  static let paneDragTerminalIdKey = "terminalId"
  static let paneDragEndedPointKey = "endedAtPoint"
}

// MARK: - Preview

#Preview {
  VStack(spacing: 0) {
    PaneHeaderView(
      title: "claude --resume abc123",
      terminalId: "test",
      snapshotProvider: { nil },
      onAction: { _ in }
    )
    Color.black
      .frame(height: 200)
  }
  .frame(width: 400)
}

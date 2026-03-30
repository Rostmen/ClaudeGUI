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

import AppKit
import GhosttyEmbed
import SwiftUI

// MARK: - SessionDragHandle (SwiftUI)

/// A small grip icon that acts as an AppKit drag source for active session rows.
///
/// Uses `NSDraggingSource` to detect when a drag ends outside all windows
/// (→ "move to new window"). The handle is a self-contained 14×14 view —
/// clicks on the grip initiate a drag, clicks elsewhere on the row go to the
/// SwiftUI List for selection. No hitTest hacks or event re-dispatch needed.
struct SessionDragHandle: View {
  let sessionId: String
  let session: ClaudeSession
  let runtime: SessionRuntimeInfo
  var onDragToNewWindow: ((String) -> Void)?

  var body: some View {
    SessionDragHandleRepresentable(
      sessionId: sessionId,
      session: session,
      runtime: runtime,
      onDragToNewWindow: onDragToNewWindow
    )
    .frame(width: 14, height: 14)
  }
}

// MARK: - SessionDragHandleRepresentable (NSViewRepresentable)

private struct SessionDragHandleRepresentable: NSViewRepresentable {
  let sessionId: String
  let session: ClaudeSession
  let runtime: SessionRuntimeInfo
  var onDragToNewWindow: ((String) -> Void)?

  func makeNSView(context: Context) -> SessionDragHandleView {
    let view = SessionDragHandleView()
    view.sessionId = sessionId
    view.session = session
    view.runtime = runtime
    view.onDragToNewWindow = onDragToNewWindow
    return view
  }

  func updateNSView(_ nsView: SessionDragHandleView, context: Context) {
    nsView.sessionId = sessionId
    nsView.session = session
    nsView.runtime = runtime
    nsView.onDragToNewWindow = onDragToNewWindow
  }
}

// MARK: - SessionDragHandleView (NSView + NSDraggingSource)

/// AppKit view that renders a grip icon and initiates drag sessions.
///
/// Follows the Ghostty `SurfaceDragSource` pattern:
/// - `mouseDown`: consumed (dedicated drag area, no propagation needed)
/// - `mouseDragged`: `beginDraggingSession` after distance threshold
/// - `draggingSession(_:endedAt:operation:)`: detects outside-window drops
/// - Hover tracking via `NSTrackingArea` for open-hand cursor
final class SessionDragHandleView: NSView, NSDraggingSource {

  var sessionId: String?
  var session: ClaudeSession?
  var runtime: SessionRuntimeInfo?
  var onDragToNewWindow: ((String) -> Void)?

  private let dragThreshold: CGFloat = 3.0
  private var dragStartLocation: NSPoint?
  private var isTracking = false
  private var escapeMonitor: Any?
  private var dragCancelledByEscape = false
  private let imageView = PassthroughImageView()

  // MARK: - Lifecycle

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupImageView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupImageView()
  }

  deinit {
    if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
  }

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { false }

  private func setupImageView() {
    let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
    if let image = NSImage(systemSymbolName: "hand.tap.fill", accessibilityDescription: "Drag") {
      imageView.image = image.withSymbolConfiguration(config) ?? image
    }
    imageView.contentTintColor = .labelColor
    imageView.imageScaling = .scaleProportionallyDown
    imageView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(imageView)
    NSLayoutConstraint.activate([
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      imageView.widthAnchor.constraint(equalTo: widthAnchor),
      imageView.heightAnchor.constraint(equalTo: heightAnchor),
    ])
  }

  // MARK: - Tracking Area (hover cursor)

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeInActiveApp],
      owner: self,
      userInfo: nil
    ))
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: isTracking ? .closedHand : .openHand)
  }

  override func mouseEntered(with event: NSEvent) {
    NSCursor.openHand.set()
  }

  override func mouseExited(with event: NSEvent) {
    NSCursor.arrow.set()
  }

  // MARK: - Mouse Handling

  override func mouseDown(with event: NSEvent) {
    // Consumed — this is a dedicated drag handle, no propagation needed
    dragStartLocation = convert(event.locationInWindow, from: nil)
  }

  override func mouseDragged(with event: NSEvent) {
    guard !isTracking, let startLocation = dragStartLocation else { return }
    let current = convert(event.locationInWindow, from: nil)
    let dx = current.x - startLocation.x
    let dy = current.y - startLocation.y
    if (dx * dx + dy * dy) > dragThreshold * dragThreshold {
      dragStartLocation = nil
      beginSessionDrag(with: event)
    }
  }

  override func mouseUp(with event: NSEvent) {
    dragStartLocation = nil
  }

  // MARK: - Drag Initiation

  private func beginSessionDrag(with event: NSEvent) {
    guard let sessionId else { return }

    // Use Transferable extension for guaranteed SwiftUI .dropDestination compatibility
    guard let pasteboardItem = sessionId.pasteboardItem() else { return }
    let item = NSDraggingItem(pasteboardWriter: pasteboardItem)

    // Render preview image lazily (only when drag actually starts)
    if let image = Self.renderPreview(session: session, runtime: runtime) {
      let mouseLocation = convert(event.locationInWindow, from: nil)
      let origin = NSPoint(
        x: mouseLocation.x - image.size.width / 2,
        y: mouseLocation.y - image.size.height / 2
      )
      item.setDraggingFrame(NSRect(origin: origin, size: image.size), contents: image)
    }

    let session = beginDraggingSession(with: [item], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = false
  }

  // MARK: - NSDraggingSource

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .withinApplication ? .move : []
  }

  func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
    isTracking = true
    dragCancelledByEscape = false
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 { self?.dragCancelledByEscape = true }
      return event
    }
    NSCursor.closedHand.set()
  }

  func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
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
    isTracking = false
    NSCursor.arrow.set()

    if operation == [] && !dragCancelledByEscape {
      let endsInWindow = NSApp.windows.contains { $0.isVisible && $0.frame.contains(screenPoint) }
      if !endsInWindow, let sessionId {
        DispatchQueue.main.async { [onDragToNewWindow] in
          onDragToNewWindow?(sessionId)
        }
      }
    }
  }

  // MARK: - Preview Rendering

  @MainActor
  static func renderPreview(session: ClaudeSession?, runtime: SessionRuntimeInfo?) -> NSImage? {
    guard let session, let runtime else { return nil }
    let content = SessionRowView(sessionModel: ClaudeSessionModel(session: session, runtime: runtime))
      .padding(8)
      .frame(width: 260)
      .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2.0
    return renderer.nsImage
  }
}

// MARK: - PassthroughImageView

/// NSImageView subclass that ignores all mouse events,
/// letting them pass through to the parent view.
private final class PassthroughImageView: NSImageView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

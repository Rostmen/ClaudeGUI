import SwiftUI

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
/// pane's `tenvySessionId` on the pasteboard for drop-to-split rearrangement.
struct PaneHeaderView: View {
  let title: String
  let tenvySessionId: String
  var isSelected: Bool = false
  var isFileDropTarget: Bool = false
  var runtimeInfo: SessionRuntimeInfo?
  /// DB-backed session record — used for persistent fields (title, etc.).
  /// Hook state comes from runtimeInfo (in-memory, not persisted to DB).
  var sessionRecord: SessionRecord?
  var isActive: Bool = false
  var ideResult: IDEDetectionResult?
  var projectPath: String?
  let snapshotProvider: () -> NSImage?
  let onAction: (PaneHeaderAction) -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var isBlinking = false
  @State private var dropHighlightPulse = false

  /// Resolved hook state — in-memory runtimeInfo is the source of truth.
  private var effectiveHookState: HookState? {
    runtimeInfo?.hookState
  }

  private var statusColor: Color {
    if isActive, let hookState = effectiveHookState {
      return hookState.statusColor
    }
    return isActive ? .green : .gray
  }

  private var shouldBlink: Bool {
    isActive && (effectiveHookState == .waiting || effectiveHookState == .waitingPermission)
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
        tenvySessionId: tenvySessionId,
        snapshotProvider: snapshotProvider,
        hasIDEButton: ideResult?.primary != nil
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

        if let ideResult, let projectPath, let primary = ideResult.primary {
          IDEHeaderButton(primary: primary, result: ideResult, projectPath: projectPath)
        }

        PaneHeaderCloseButton {
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

// MARK: - Preview

#Preview {
  VStack(spacing: 0) {
    PaneHeaderView(
      title: "claude --resume abc123",
      tenvySessionId: "test",
      snapshotProvider: { nil },
      onAction: { _ in }
    )
    Color.black
      .frame(height: 200)
  }
  .frame(width: 400)
}

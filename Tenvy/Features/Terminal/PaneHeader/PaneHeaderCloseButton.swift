import SwiftUI

/// Close button with hover highlight for the pane header.
struct PaneHeaderCloseButton: View {
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.primary)
        .frame(width: 20, height: 20)
        .background(isHovering ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }
}

#Preview {
  PaneHeaderCloseButton(action: {})
    .padding()
}

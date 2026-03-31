import SwiftUI

/// Compact IDE button for the pane header — icon-only with optional dropdown.
/// Shows the primary IDE's app icon. When multiple IDEs are available, a chevron
/// dropdown lets the user pick an alternative.
struct IDEHeaderButton: View {
  let primary: DetectedIDE
  let result: IDEDetectionResult
  let projectPath: String

  @State private var isHovering = false

  private var iconView: some View {
    Image(nsImage: primary.icon.resizedMaintainingAspectRatio(width: 16, height: 16))
  }

  var body: some View {
    Group {
      if result.hasAlternatives {
        HStack(spacing: 0) {
          Button {
            IDEDetectionService.open(projectPath: projectPath, with: primary)
          } label: {
            iconView
          }
          .buttonStyle(.borderless)
          Menu {
            Button {
              IDEDetectionService.open(projectPath: projectPath, with: primary)
            } label: {
              Label {
                Text(primary.name)
              }
              icon: {
                iconView
              }
            }
            
            Divider()
            
            ForEach(result.alternatives) { ide in
              Button {
                IDEDetectionService.open(projectPath: projectPath, with: ide)
              } label: {
                Label {
                  Text(ide.name)
                } icon: {
                  Image(nsImage: ide.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                }
              }
            }
          } label: {
            
          }
          .menuStyle(.borderlessButton)
        }
        .fixedSize(horizontal: false, vertical: true)
        
      } else {
        Button {
          IDEDetectionService.open(projectPath: projectPath, with: primary)
        } label: {
          iconView
        }
        .buttonStyle(.plain)
      }
    }
    .padding(2)
    .onHover { isHovering = $0 }
    .background {
      RoundedRectangle(cornerRadius: 4)
        .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
    }
    .help("Open in \(primary.name)")
  }
}

// MARK: - Previews

#Preview("Single IDE") {
  let icon = NSWorkspace.shared.icon(forFile: "/Applications/Xcode.app")
  IDEHeaderButton(
    primary: DetectedIDE(
      id: "com.apple.dt.Xcode",
      name: "Xcode",
      bundleIdentifier: "com.apple.dt.Xcode",
      appURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
      icon: icon,
      isProjectSpecific: true
    ),
    result: IDEDetectionResult(
      primary: DetectedIDE(
        id: "com.apple.dt.Xcode",
        name: "Xcode",
        bundleIdentifier: "com.apple.dt.Xcode",
        appURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
        icon: icon,
        isProjectSpecific: true
      ),
      alternatives: []
    ),
    projectPath: "/tmp"
  )
  .padding()
}

extension NSImage {
  func resizedMaintainingAspectRatio(width: CGFloat, height: CGFloat) -> NSImage {
    let ratioX = width / size.width
    let ratioY = height / size.height
    let ratio = min(ratioX, ratioY) // Use the smaller ratio to fit within the bounds
    
    let newWidth = size.width * ratio
    let newHeight = size.height * ratio
    let newSize = NSSize(width: newWidth, height: newHeight)
    
    // Create a new image with the calculated proportional size
    let image = NSImage(size: newSize, flipped: false) { destRect in
      NSGraphicsContext.current?.imageInterpolation = .high
      self.draw(
        in: destRect,
        from: NSRect(origin: .zero, size: self.size),
        operation: .copy,
        fraction: 1
      )
      return true
    }
    return image
  }
}

#Preview("Multiple IDEs") {
  let xcodeIcon = NSWorkspace.shared.icon(forFile: "/Applications/Xcode.app")
  let vscodeIcon = NSWorkspace.shared.icon(forFile: "/Applications/Visual Studio Code.app")
  let xcode = DetectedIDE(
    id: "com.apple.dt.Xcode",
    name: "Xcode",
    bundleIdentifier: "com.apple.dt.Xcode",
    appURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
    icon: xcodeIcon,
    isProjectSpecific: true
  )
  let vscode = DetectedIDE(
    id: "com.microsoft.VSCode",
    name: "VS Code",
    bundleIdentifier: "com.microsoft.VSCode",
    appURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
    icon: vscodeIcon,
    isProjectSpecific: false
  )
  IDEHeaderButton(
    primary: xcode,
    result: IDEDetectionResult(
      primary: xcode,
      alternatives: [vscode]
    ),
    projectPath: "/tmp"
  )
  .padding()
}

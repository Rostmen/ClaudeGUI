import AppKit

// MARK: - Models

/// Static catalog entry describing a known IDE.
struct IDEDefinition {
  let name: String
  let bundleIdentifier: String
  /// File/directory names that indicate this IDE is the primary match.
  /// Empty for general-purpose editors.
  let indicatorPatterns: [String]
  /// Suffix patterns (e.g. ".sln", ".csproj") matched against file extensions.
  let suffixPatterns: [String]
  /// Whether this IDE can open any folder regardless of project type.
  let isGeneralPurpose: Bool

  init(
    name: String,
    bundleIdentifier: String,
    indicatorPatterns: [String] = [],
    suffixPatterns: [String] = [],
    isGeneralPurpose: Bool = false
  ) {
    self.name = name
    self.bundleIdentifier = bundleIdentifier
    self.indicatorPatterns = indicatorPatterns
    self.suffixPatterns = suffixPatterns
    self.isGeneralPurpose = isGeneralPurpose
  }
}

/// A resolved IDE that is both relevant to the current project and installed.
struct DetectedIDE: Identifiable, Hashable {
  let id: String // bundleIdentifier
  let name: String
  let bundleIdentifier: String
  let appURL: URL
  let icon: NSImage
  /// True if this IDE matched a project-specific indicator file.
  let isProjectSpecific: Bool

  static func == (lhs: DetectedIDE, rhs: DetectedIDE) -> Bool {
    lhs.bundleIdentifier == rhs.bundleIdentifier
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(bundleIdentifier)
  }
}

/// Detection result for a given project path.
struct IDEDetectionResult {
  /// Best-match IDE (project-specific if available, otherwise first general-purpose).
  let primary: DetectedIDE?
  /// All alternatives, ordered: project-specific first, then general-purpose. Primary excluded.
  let alternatives: [DetectedIDE]

  var isEmpty: Bool { primary == nil }
  var hasAlternatives: Bool { !alternatives.isEmpty }

  static let empty = IDEDetectionResult(primary: nil, alternatives: [])
}

// MARK: - Service

enum IDEDetectionService {

  // MARK: - IDE Catalog

  static let knownIDEs: [IDEDefinition] = [
    // Project-specific IDEs
    IDEDefinition(
      name: "Xcode",
      bundleIdentifier: "com.apple.dt.Xcode",
      suffixPatterns: [".xcodeproj", ".xcworkspace"]
    ),
    IDEDefinition(
      name: "Xcode",
      bundleIdentifier: "com.apple.dt.Xcode",
      indicatorPatterns: ["Package.swift"]
    ),
    IDEDefinition(
      name: "Android Studio",
      bundleIdentifier: "com.google.android.studio",
      indicatorPatterns: ["build.gradle", "build.gradle.kts", "settings.gradle", "pubspec.yaml"]
    ),
    IDEDefinition(
      name: "IntelliJ IDEA",
      bundleIdentifier: "com.jetbrains.intellij",
      indicatorPatterns: [".idea", "pom.xml"]
    ),
    IDEDefinition(
      name: "RustRover",
      bundleIdentifier: "com.jetbrains.rustrover",
      indicatorPatterns: ["Cargo.toml"]
    ),
    IDEDefinition(
      name: "Rider",
      bundleIdentifier: "com.jetbrains.rider",
      suffixPatterns: [".sln", ".csproj"]
    ),
    IDEDefinition(
      name: "GoLand",
      bundleIdentifier: "com.jetbrains.goland",
      indicatorPatterns: ["go.mod"]
    ),
    IDEDefinition(
      name: "WebStorm",
      bundleIdentifier: "com.jetbrains.WebStorm",
      indicatorPatterns: ["package.json", "tsconfig.json"]
    ),
    IDEDefinition(
      name: "RubyMine",
      bundleIdentifier: "com.jetbrains.rubymine",
      indicatorPatterns: ["Gemfile"]
    ),
    IDEDefinition(
      name: "PyCharm",
      bundleIdentifier: "com.jetbrains.pycharm",
      indicatorPatterns: ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile"]
    ),

    // General-purpose editors
    IDEDefinition(
      name: "VS Code",
      bundleIdentifier: "com.microsoft.VSCode",
      indicatorPatterns: [".vscode"],
      isGeneralPurpose: true
    ),
    IDEDefinition(
      name: "Cursor",
      bundleIdentifier: "com.todesktop.230313mzl4w4u92",
      isGeneralPurpose: true
    ),
    IDEDefinition(
      name: "Windsurf",
      bundleIdentifier: "com.codeium.windsurf",
      isGeneralPurpose: true
    ),
    IDEDefinition(
      name: "Zed",
      bundleIdentifier: "dev.zed.Zed",
      isGeneralPurpose: true
    ),
    IDEDefinition(
      name: "Sublime Text",
      bundleIdentifier: "com.sublimetext.4",
      isGeneralPurpose: true
    ),
    IDEDefinition(
      name: "Nova",
      bundleIdentifier: "com.panic.Nova",
      isGeneralPurpose: true
    ),
    IDEDefinition(
      name: "Fleet",
      bundleIdentifier: "com.jetbrains.fleet",
      isGeneralPurpose: true
    ),
  ]

  /// Detect IDEs for a given project path.
  static func detect(projectPath: String) -> IDEDetectionResult {
    let fm = FileManager.default
    let children: Set<String>
    if let contents = try? fm.contentsOfDirectory(atPath: projectPath) {
      children = Set(contents)
    } else {
      children = []
    }

    // Track which bundle IDs we've already added (some IDEs appear in multiple catalog entries)
    var seenBundleIDs = Set<String>()
    var projectSpecific: [DetectedIDE] = []
    var generalPurpose: [DetectedIDE] = []

    for definition in knownIDEs {
      // Skip if already detected this IDE
      guard !seenBundleIDs.contains(definition.bundleIdentifier) else { continue }

      // Check if installed
      guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: definition.bundleIdentifier) else {
        continue
      }

      // Check if indicators match
      let hasIndicatorMatch = definition.indicatorPatterns.contains { children.contains($0) }
      let hasSuffixMatch = !definition.suffixPatterns.isEmpty && children.contains { fileName in
        definition.suffixPatterns.contains { suffix in fileName.hasSuffix(suffix) }
      }
      let isProjectSpecific = hasIndicatorMatch || hasSuffixMatch

      // For non-general-purpose IDEs, only include if they have a project match
      if !definition.isGeneralPurpose && !isProjectSpecific {
        continue
      }

      let icon = NSWorkspace.shared.icon(forFile: appURL.path)
      icon.size = NSSize(width: 16, height: 16)

      let detected = DetectedIDE(
        id: definition.bundleIdentifier,
        name: definition.name,
        bundleIdentifier: definition.bundleIdentifier,
        appURL: appURL,
        icon: icon,
        isProjectSpecific: isProjectSpecific
      )

      seenBundleIDs.insert(definition.bundleIdentifier)

      if isProjectSpecific {
        projectSpecific.append(detected)
      } else {
        generalPurpose.append(detected)
      }
    }

    // Combine: project-specific first, then general-purpose
    let all = projectSpecific + generalPurpose

    guard let primary = all.first else {
      return .empty
    }

    return IDEDetectionResult(
      primary: primary,
      alternatives: Array(all.dropFirst())
    )
  }

  /// Open a folder in a specific IDE.
  static func open(projectPath: String, with ide: DetectedIDE) {
    let projectURL = URL(fileURLWithPath: projectPath)
    let config = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.open([projectURL], withApplicationAt: ide.appURL, configuration: config)
  }
}

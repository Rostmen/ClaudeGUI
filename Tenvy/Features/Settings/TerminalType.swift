/// Terminal rendering type
enum TerminalType: String, CaseIterable, Codable {
  case swiftTerm = "swiftterm"
  case ghostty = "ghostty"

  /// Human-readable display name for the terminal type
  var displayName: String {
    switch self {
    case .swiftTerm:
      return "SwiftTerm (Default)"
    case .ghostty:
      return "Ghostty (Experimental)"
    }
  }
}

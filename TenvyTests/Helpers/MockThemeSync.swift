import Foundation
@testable import Tenvy

/// No-op theme sync mock for testing. Records all apply calls.
final class MockThemeSync: ThemeSyncing {
  private(set) var appliedModes: [AppearanceMode] = []

  func apply(_ mode: AppearanceMode) {
    appliedModes.append(mode)
  }
}

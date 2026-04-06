import Foundation
@testable import Tenvy

/// Creates an isolated AppSettings instance for testing.
/// Uses an in-memory UserDefaults suite and mock dependencies.
enum TestAppSettings {
  static func make(
    defaults: UserDefaults? = nil,
    keychainService: KeychainServiceProtocol = MockKeychainService(),
    themeSync: ThemeSyncing = MockThemeSync(),
    notificationCenter: NotificationCenter = NotificationCenter()
  ) -> AppSettings {
    let suite = defaults ?? UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    return AppSettings(
      defaults: suite,
      keychainService: keychainService,
      themeSync: themeSync,
      notificationCenter: notificationCenter
    )
  }
}

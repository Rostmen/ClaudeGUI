// MIT License
// Copyright (c) 2026 Rostyslav Kobizsky
// See LICENSE for full terms.

import Foundation
import Testing
@testable import Tenvy

struct AppSettingsDefaultsTests {

  @Test("fresh instance has correct default values")
  func defaults() {
    let settings = TestAppSettings.make()

    #expect(settings.gitChangesEnabled == false)
    #expect(settings.hookPromptDismissed == false)
    #expect(settings.notificationPromptDismissed == false)
    #expect(settings.lastSeenVersion == "")
    #expect(settings.customEnvironmentVariables == [:])
    #expect(settings.shellInitScript == AppSettings.defaultShellInitScript)
    #expect(settings.worktreeLocation == .defaultClaude)
    #expect(settings.customWorktreeRoot == "")
    #expect(settings.appearanceMode == .system)
  }
}

struct AppSettingsPersistenceTests {

  @Test("bool property persists to UserDefaults")
  func boolPersistence() {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let settings = TestAppSettings.make(defaults: defaults)

    settings.gitChangesEnabled = true
    #expect(defaults.bool(forKey: "settings.gitChangesEnabled") == true)

    settings.hookPromptDismissed = true
    #expect(defaults.bool(forKey: "settings.hookPromptDismissed") == true)

    settings.notificationPromptDismissed = true
    #expect(defaults.bool(forKey: "settings.notificationPromptDismissed") == true)
  }

  @Test("string property persists to UserDefaults")
  func stringPersistence() {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let settings = TestAppSettings.make(defaults: defaults)

    settings.lastSeenVersion = "2.0.0"
    #expect(defaults.string(forKey: "settings.lastSeenVersion") == "2.0.0")

    settings.shellInitScript = "echo hello"
    #expect(defaults.string(forKey: "settings.shellInitScript") == "echo hello")

    settings.customWorktreeRoot = "/custom/path"
    #expect(defaults.string(forKey: "settings.customWorktreeRoot") == "/custom/path")
  }

  @Test("worktreeLocation persists raw value to UserDefaults")
  func worktreeLocationPersistence() {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let settings = TestAppSettings.make(defaults: defaults)

    settings.worktreeLocation = .custom
    #expect(defaults.string(forKey: "settings.worktreeLocation") == "custom")

    settings.worktreeLocation = .defaultClaude
    #expect(defaults.string(forKey: "settings.worktreeLocation") == "default")
  }

  @Test("loads persisted values from UserDefaults on init")
  func loadsFromDefaults() {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    defaults.set(true, forKey: "settings.gitChangesEnabled")
    defaults.set("1.5.0", forKey: "settings.lastSeenVersion")
    defaults.set("custom", forKey: "settings.worktreeLocation")
    defaults.set("/my/worktrees", forKey: "settings.customWorktreeRoot")
    defaults.set("dark", forKey: "settings.appearanceMode")

    let settings = TestAppSettings.make(defaults: defaults)

    #expect(settings.gitChangesEnabled == true)
    #expect(settings.lastSeenVersion == "1.5.0")
    #expect(settings.worktreeLocation == .custom)
    #expect(settings.customWorktreeRoot == "/my/worktrees")
    #expect(settings.appearanceMode == .dark)
  }
}

struct AppSettingsKeychainTests {

  @Test("customEnvironmentVariables saves to keychain on set")
  func savesToKeychain() {
    let keychain = MockKeychainService()
    let settings = TestAppSettings.make(keychainService: keychain)

    settings.customEnvironmentVariables = ["API_KEY": "secret"]

    #expect(keychain.saveCallCount == 1)
    let loaded: [String: String]? = keychain.load([String: String].self, account: AppSettings.envVarsKeychainAccount)
    #expect(loaded == ["API_KEY": "secret"])
  }

  @Test("loads environment variables from keychain on init")
  func loadsFromKeychain() {
    let keychain = MockKeychainService()
    keychain.save(["TOKEN": "abc123"], account: AppSettings.envVarsKeychainAccount)

    let settings = TestAppSettings.make(keychainService: keychain)

    #expect(settings.customEnvironmentVariables == ["TOKEN": "abc123"])
  }
}

struct AppSettingsThemeSyncTests {

  @Test("syncs theme on init")
  func syncsOnInit() {
    let themeSync = MockThemeSync()
    _ = TestAppSettings.make(themeSync: themeSync)

    #expect(themeSync.appliedModes.count == 1)
    #expect(themeSync.appliedModes.first == .system)
  }

  @Test("syncs theme on appearance mode change")
  func syncsOnChange() {
    let themeSync = MockThemeSync()
    let settings = TestAppSettings.make(themeSync: themeSync)

    settings.appearanceMode = .dark
    settings.appearanceMode = .light

    // 1 from init (.system) + 2 from changes
    #expect(themeSync.appliedModes == [.system, .dark, .light])
  }
}

struct AppSettingsNotificationTests {

  @Test("posts notification on appearance mode change")
  func postsNotification() {
    let nc = NotificationCenter()
    let settings = TestAppSettings.make(notificationCenter: nc)

    var received = false
    let observer = nc.addObserver(forName: .appearanceModeDidChange, object: nil, queue: nil) { _ in
      received = true
    }
    defer { nc.removeObserver(observer) }

    settings.appearanceMode = .dark

    #expect(received == true)
  }

  @Test("does not post notification on init")
  func noNotificationOnInit() {
    let nc = NotificationCenter()
    var received = false
    let observer = nc.addObserver(forName: .appearanceModeDidChange, object: nil, queue: nil) { _ in
      received = true
    }

    _ = TestAppSettings.make(notificationCenter: nc)

    nc.removeObserver(observer)
    #expect(received == false)
  }
}

struct AppSettingsMigrationTests {

  @Test("migrates old sourceZshrc=true to default shell init script")
  func migratesSourceZshrcTrue() {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    defaults.set(true, forKey: "settings.sourceZshrc")

    let settings = TestAppSettings.make(defaults: defaults)

    #expect(settings.shellInitScript == AppSettings.defaultShellInitScript)
  }

  @Test("migrates old sourceZshrc=false to empty script")
  func migratesSourceZshrcFalse() {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    defaults.set(false, forKey: "settings.sourceZshrc")

    let settings = TestAppSettings.make(defaults: defaults)

    #expect(settings.shellInitScript == "")
  }

  @Test("existing shellInitScript takes precedence over sourceZshrc migration")
  func existingScriptWins() {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    defaults.set("custom script", forKey: "settings.shellInitScript")
    defaults.set(true, forKey: "settings.sourceZshrc")

    let settings = TestAppSettings.make(defaults: defaults)

    #expect(settings.shellInitScript == "custom script")
  }

  @Test("migrates env vars from UserDefaults to keychain")
  func migratesEnvVarsToKeychain() {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let vars = ["KEY": "value"]
    defaults.set(try! JSONEncoder().encode(vars), forKey: "settings.customEnvironmentVariables")

    let keychain = MockKeychainService()
    let settings = TestAppSettings.make(defaults: defaults, keychainService: keychain)

    #expect(settings.customEnvironmentVariables == ["KEY": "value"])
    #expect(keychain.saveCallCount == 1)
    // Old UserDefaults key should be removed
    #expect(defaults.data(forKey: "settings.customEnvironmentVariables") == nil)
  }
}

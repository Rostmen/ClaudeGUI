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

import Foundation
import SwiftUI

// MARK: - AppearanceMode

enum AppearanceMode: String, CaseIterable {
  case system, light, dark

  var displayName: String {
    switch self {
    case .system: return "System"
    case .light:  return "Light"
    case .dark:   return "Dark"
    }
  }

  /// Returns `nil` for System so SwiftUI follows the OS automatically.
  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light:  return .light
    case .dark:   return .dark
    }
  }
}

// MARK: - WorktreeLocation

enum WorktreeLocation: String, CaseIterable {
  case defaultClaude = "default"
  case custom = "custom"

  var displayName: String {
    switch self {
    case .defaultClaude: return "Default (.claude/worktrees)"
    case .custom: return "Custom"
    }
  }
}

// MARK: - AppSettings

/// App-wide settings with injected dependencies for testability.
@Observable
final class AppSettings {
  static let shared = AppSettings()

  // MARK: - Dependencies

  let defaults: UserDefaults
  let keychainService: KeychainServiceProtocol
  let themeSync: ThemeSyncing
  let notificationCenter: NotificationCenter

  // MARK: - Settings Properties

  /// Enable git changes feature
  var gitChangesEnabled: Bool {
    didSet { defaults.set(gitChangesEnabled, forKey: "settings.gitChangesEnabled") }
  }

  /// User has dismissed the hook installation prompt permanently
  var hookPromptDismissed: Bool {
    didSet { defaults.set(hookPromptDismissed, forKey: "settings.hookPromptDismissed") }
  }

  /// User has dismissed the notification permission prompt permanently
  var notificationPromptDismissed: Bool {
    didSet { defaults.set(notificationPromptDismissed, forKey: "settings.notificationPromptDismissed") }
  }

  /// The last app version whose release notes were shown to the user
  var lastSeenVersion: String {
    didSet { defaults.set(lastSeenVersion, forKey: "settings.lastSeenVersion") }
  }

  static let envVarsKeychainAccount = "environmentVariables"

  /// Custom environment variables injected into every terminal session (stored in Keychain)
  var customEnvironmentVariables: [String: String] {
    didSet {
      keychainService.save(customEnvironmentVariables, account: Self.envVarsKeychainAccount)
    }
  }

  /// Shell init script executed before launching claude or a plain terminal.
  var shellInitScript: String {
    didSet { defaults.set(shellInitScript, forKey: "settings.shellInitScript") }
  }

  /// The default shell init script that sources ~/.zshrc.
  static let defaultShellInitScript = "[ -f \"$HOME/.zshrc\" ] && source \"$HOME/.zshrc\" 2>/dev/null;"

  /// Where worktrees are created: relative to project (.claude/worktrees) or a custom folder
  var worktreeLocation: WorktreeLocation {
    didSet { defaults.set(worktreeLocation.rawValue, forKey: "settings.worktreeLocation") }
  }

  /// Custom root folder for worktrees (used when worktreeLocation == .custom)
  var customWorktreeRoot: String {
    didSet { defaults.set(customWorktreeRoot, forKey: "settings.customWorktreeRoot") }
  }

  /// Appearance mode (System / Light / Dark)
  var appearanceMode: AppearanceMode {
    didSet {
      defaults.set(appearanceMode.rawValue, forKey: "settings.appearanceMode")
      themeSync.apply(appearanceMode)
      notificationCenter.post(name: .appearanceModeDidChange, object: nil)
    }
  }

  // MARK: - Init

  init(
    defaults: UserDefaults = .standard,
    keychainService: KeychainServiceProtocol = KeychainService(),
    themeSync: ThemeSyncing = ClaudeThemeSync(),
    notificationCenter: NotificationCenter = .default
  ) {
    self.defaults = defaults
    self.keychainService = keychainService
    self.themeSync = themeSync
    self.notificationCenter = notificationCenter

    // Load initial values from UserDefaults
    self.gitChangesEnabled = defaults.object(forKey: "settings.gitChangesEnabled") as? Bool ?? false
    self.hookPromptDismissed = defaults.object(forKey: "settings.hookPromptDismissed") as? Bool ?? false
    self.notificationPromptDismissed = defaults.object(forKey: "settings.notificationPromptDismissed") as? Bool ?? false
    self.lastSeenVersion = defaults.object(forKey: "settings.lastSeenVersion") as? String ?? ""

    // Load env vars from Keychain, with one-time migration from UserDefaults
    if let vars = keychainService.load([String: String].self, account: Self.envVarsKeychainAccount) {
      self.customEnvironmentVariables = vars
    } else if let data = defaults.data(forKey: "settings.customEnvironmentVariables"),
              let vars = try? JSONDecoder().decode([String: String].self, from: data) {
      // Migrate from UserDefaults to Keychain
      self.customEnvironmentVariables = vars
      keychainService.save(vars, account: Self.envVarsKeychainAccount)
      defaults.removeObject(forKey: "settings.customEnvironmentVariables")
    } else {
      self.customEnvironmentVariables = [:]
    }

    // Migration: convert old sourceZshrc bool to shellInitScript string
    if let existingScript = defaults.string(forKey: "settings.shellInitScript") {
      self.shellInitScript = existingScript
    } else if let oldSourceZshrc = defaults.object(forKey: "settings.sourceZshrc") as? Bool {
      self.shellInitScript = oldSourceZshrc ? AppSettings.defaultShellInitScript : ""
    } else {
      self.shellInitScript = AppSettings.defaultShellInitScript
    }

    // Load worktree location setting
    if let rawValue = defaults.string(forKey: "settings.worktreeLocation"),
       let location = WorktreeLocation(rawValue: rawValue) {
      self.worktreeLocation = location
    } else {
      self.worktreeLocation = .defaultClaude
    }
    self.customWorktreeRoot = defaults.string(forKey: "settings.customWorktreeRoot") ?? ""

    // Load appearance mode, defaulting to System
    if let rawValue = defaults.object(forKey: "settings.appearanceMode") as? String,
       let mode = AppearanceMode(rawValue: rawValue) {
      self.appearanceMode = mode
    } else {
      self.appearanceMode = .system
    }

    // Sync Claude CLI theme on launch
    themeSync.apply(self.appearanceMode)
  }
}

/// App metadata
enum AppInfo {
  static var appName: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Tenvy"
  }

  static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
  }

  static var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
  }

  static var author: String {
    "Rostyslav Kobizsky"
  }

  static var copyright: String {
    Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026"
  }
}

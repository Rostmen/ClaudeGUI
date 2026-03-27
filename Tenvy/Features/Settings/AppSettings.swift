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

/// App-wide settings stored in UserDefaults
@Observable
final class AppSettings {
  static let shared = AppSettings()

  /// Enable git changes feature
  var gitChangesEnabled: Bool {
    didSet { UserDefaults.standard.set(gitChangesEnabled, forKey: "settings.gitChangesEnabled") }
  }

  /// User has dismissed the hook installation prompt permanently
  var hookPromptDismissed: Bool {
    didSet { UserDefaults.standard.set(hookPromptDismissed, forKey: "settings.hookPromptDismissed") }
  }

  /// User has dismissed the notification permission prompt permanently
  var notificationPromptDismissed: Bool {
    didSet { UserDefaults.standard.set(notificationPromptDismissed, forKey: "settings.notificationPromptDismissed") }
  }

  /// The last app version whose release notes were shown to the user
  var lastSeenVersion: String {
    didSet { UserDefaults.standard.set(lastSeenVersion, forKey: "settings.lastSeenVersion") }
  }

  /// Custom environment variables injected into every terminal session
  var customEnvironmentVariables: [String: String] {
    didSet {
      if let data = try? JSONEncoder().encode(customEnvironmentVariables) {
        UserDefaults.standard.set(data, forKey: "settings.customEnvironmentVariables")
      }
    }
  }

  /// Whether to source ~/.zshrc before launching claude (default: true)
  var sourceZshrc: Bool {
    didSet { UserDefaults.standard.set(sourceZshrc, forKey: "settings.sourceZshrc") }
  }

  /// Terminal type to use for sessions
  var terminalType: TerminalType {
    didSet { UserDefaults.standard.set(terminalType.rawValue, forKey: "settings.terminalType") }
  }

  private init() {
    // Load initial values from UserDefaults
    self.gitChangesEnabled = UserDefaults.standard.object(forKey: "settings.gitChangesEnabled") as? Bool ?? false
    self.hookPromptDismissed = UserDefaults.standard.object(forKey: "settings.hookPromptDismissed") as? Bool ?? false
    self.notificationPromptDismissed = UserDefaults.standard.object(forKey: "settings.notificationPromptDismissed") as? Bool ?? false
    self.lastSeenVersion = UserDefaults.standard.object(forKey: "settings.lastSeenVersion") as? String ?? ""
    if let data = UserDefaults.standard.data(forKey: "settings.customEnvironmentVariables"),
       let vars = try? JSONDecoder().decode([String: String].self, from: data) {
      self.customEnvironmentVariables = vars
    } else {
      self.customEnvironmentVariables = [:]
    }
    self.sourceZshrc = UserDefaults.standard.object(forKey: "settings.sourceZshrc") as? Bool ?? true

    // Load terminal type, defaulting to SwiftTerm
    if let rawValue = UserDefaults.standard.object(forKey: "settings.terminalType") as? String,
       let type = TerminalType(rawValue: rawValue) {
      self.terminalType = type
    } else {
      self.terminalType = .swiftTerm
    }
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

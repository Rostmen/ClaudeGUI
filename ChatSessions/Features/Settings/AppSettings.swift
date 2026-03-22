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

  /// Enable file tree browser feature
  var fileTreeEnabled: Bool {
    didSet { UserDefaults.standard.set(fileTreeEnabled, forKey: "settings.fileTreeEnabled") }
  }

  /// Enable git changes feature
  var gitChangesEnabled: Bool {
    didSet { UserDefaults.standard.set(gitChangesEnabled, forKey: "settings.gitChangesEnabled") }
  }

  /// User has dismissed the hook installation prompt permanently
  var hookPromptDismissed: Bool {
    didSet { UserDefaults.standard.set(hookPromptDismissed, forKey: "settings.hookPromptDismissed") }
  }

  private init() {
    // Load initial values from UserDefaults
    self.fileTreeEnabled = UserDefaults.standard.object(forKey: "settings.fileTreeEnabled") as? Bool ?? true
    self.gitChangesEnabled = UserDefaults.standard.object(forKey: "settings.gitChangesEnabled") as? Bool ?? true
    self.hookPromptDismissed = UserDefaults.standard.object(forKey: "settings.hookPromptDismissed") as? Bool ?? false
  }
}

/// App metadata
enum AppInfo {
  static var appName: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ChatSessions"
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

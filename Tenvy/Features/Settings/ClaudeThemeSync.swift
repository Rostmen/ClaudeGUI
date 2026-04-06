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

import AppKit

/// Abstraction for theme syncing — injectable for testing.
protocol ThemeSyncing {
  func apply(_ mode: AppearanceMode)
}

/// Writes the `theme` key to `~/.claude.json` so Claude CLI output colors
/// match Tenvy's current appearance setting.
struct ClaudeThemeSync: ThemeSyncing {
  private let claudeJsonURL: URL

  init(claudeJsonURL: URL = URL(fileURLWithPath: NSHomeDirectory() + "/.claude.json")) {
    self.claudeJsonURL = claudeJsonURL
  }

  /// Resolves the effective theme string ("dark" or "light") for a given mode,
  /// falling back to the current system appearance for System mode.
  func apply(_ mode: AppearanceMode) {
    let theme: String
    switch mode {
    case .dark:   theme = "dark"
    case .light:  theme = "light"
    case .system:
      let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      theme = isDark ? "dark" : "light"
    }
    writeTheme(theme)
  }

  /// Static convenience for callers that don't hold an instance (e.g. ContentView).
  static func apply(_ mode: AppearanceMode) {
    ClaudeThemeSync().apply(mode)
  }

  private func writeTheme(_ theme: String) {
    do {
      var json: [String: Any]
      if let data = try? Data(contentsOf: claudeJsonURL),
         let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        json = existing
      } else {
        json = [:]
      }

      json["theme"] = theme

      let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
      try data.write(to: claudeJsonURL, options: .atomic)
    } catch {
      // Non-fatal — Claude CLI will just use its own default
    }
  }
}

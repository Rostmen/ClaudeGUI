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

import SwiftUI

enum ClaudeTheme {
  // Background colors
  static let background = SwiftUI.Color.black.opacity(0.7)
  static let sidebar = SwiftUI.Color.black.opacity(0.5)
  static let surface = SwiftUI.Color(hex: "#1a1a1a")

  // Text colors — use system-adaptive primaries so dark/light mode flips automatically
  static let textPrimary = SwiftUI.Color.primary
  static let textSecondary = SwiftUI.Color.secondary
  static let textTertiary = SwiftUI.Color.secondary.opacity(0.6)

  // Accent colors
  static let accent = SwiftUI.Color(hex: "#da7756")
  static let accentHover = SwiftUI.Color(hex: "#e8896a")

  // Terminal colors
  static let terminalBackground = SwiftUI.Color.black.opacity(0.001) // Nearly transparent
  static let terminalForeground = SwiftUI.Color(hex: "#eaeaea")
  static let terminalCursor = SwiftUI.Color(hex: "#da7756")

  // Selection
  static let selection = SwiftUI.Color(hex: "#3d3d5c")
}

extension SwiftUI.Color {
  init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch hex.count {
    case 3: // RGB (12-bit)
      (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6: // RGB (24-bit)
      (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8: // ARGB (32-bit)
      (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default:
      (a, r, g, b) = (255, 0, 0, 0)
    }
    self.init(
      .sRGB,
      red: Double(r) / 255,
      green: Double(g) / 255,
      blue: Double(b) / 255,
      opacity: Double(a) / 255
    )
  }

  var nsColor: NSColor {
    NSColor(self)
  }
}

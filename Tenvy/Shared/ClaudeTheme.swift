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
import SwiftTerm

enum ClaudeTheme {
  // Background colors
  static let background = SwiftUI.Color.black.opacity(0.7)
  static let sidebar = SwiftUI.Color.black.opacity(0.5)
  static let surface = SwiftUI.Color(hex: "#1a1a1a")

  // Text colors
  static let textPrimary = SwiftUI.Color(hex: "#eaeaea")
  static let textSecondary = SwiftUI.Color(hex: "#8b8b9e")
  static let textTertiary = SwiftUI.Color(hex: "#5a5a6e")  // Dimmer for dividers

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

enum ClaudeTerminalColors {
  // ANSI color palette for SwiftTerm (16 colors)
  // Order: black, red, green, yellow, blue, magenta, cyan, white (normal then bright)
  static let palette: [SwiftTerm.Color] = [
    // Normal colors (0-7)
    SwiftTerm.Color(red: 0x00, green: 0x00, blue: 0x00),  // black
    SwiftTerm.Color(red: 0xff, green: 0x6b, blue: 0x6b),  // red
    SwiftTerm.Color(red: 0x4e, green: 0xcd, blue: 0xc4),  // green
    SwiftTerm.Color(red: 0xff, green: 0xe6, blue: 0x6d),  // yellow
    SwiftTerm.Color(red: 0x6c, green: 0x9b, blue: 0xd1),  // blue
    SwiftTerm.Color(red: 0xc7, green: 0x92, blue: 0xea),  // magenta
    SwiftTerm.Color(red: 0x89, green: 0xdd, blue: 0xff),  // cyan
    SwiftTerm.Color(red: 0xd0, green: 0xd0, blue: 0xd0),  // white

    // Bright colors (8-15)
    SwiftTerm.Color(red: 0x50, green: 0x50, blue: 0x50),  // bright black (gray)
    SwiftTerm.Color(red: 0xff, green: 0x87, blue: 0x87),  // bright red
    SwiftTerm.Color(red: 0x7e, green: 0xe2, blue: 0xd9),  // bright green
    SwiftTerm.Color(red: 0xff, green: 0xf3, blue: 0xa3),  // bright yellow
    SwiftTerm.Color(red: 0x8c, green: 0xb4, blue: 0xe8),  // bright blue
    SwiftTerm.Color(red: 0xd4, green: 0xa6, blue: 0xf5),  // bright magenta
    SwiftTerm.Color(red: 0xa6, green: 0xee, blue: 0xff),  // bright cyan
    SwiftTerm.Color(red: 0xea, green: 0xea, blue: 0xea),  // bright white
  ]
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

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

enum ClaudeTerminalColors {
  // SwiftTerm.Color uses UInt16 (0–65535). Convert 8-bit values with * 257.
  private static func c(_ r: Int, _ g: Int, _ b: Int) -> SwiftTerm.Color {
    SwiftTerm.Color(red: UInt16(r * 257), green: UInt16(g * 257), blue: UInt16(b * 257))
  }

  // ANSI palette — dark background (matches original proven palette)
  static let darkPalette: [SwiftTerm.Color] = [
    c(  0,   0,   0),  //  0 black
    c(194,  54,  33),  //  1 red
    c( 37, 188,  36),  //  2 green
    c(173, 173,  39),  //  3 yellow
    c( 73,  46, 225),  //  4 blue
    c(211,  56, 211),  //  5 magenta
    c( 51, 187, 200),  //  6 cyan
    c(203, 204, 205),  //  7 white
    c(129, 131, 131),  //  8 bright black (gray)
    c(252,  57,  31),  //  9 bright red
    c( 49, 231,  34),  // 10 bright green
    c(234, 236,  35),  // 11 bright yellow
    c( 88,  51, 255),  // 12 bright blue
    c(249,  53, 248),  // 13 bright magenta
    c( 20, 240, 240),  // 14 bright cyan
    c(233, 235, 235),  // 15 bright white
  ]

  // ANSI palette — light background (dark, saturated for contrast on white)
  static let lightPalette: [SwiftTerm.Color] = [
    c( 26,  26,  26),  //  0 black → near black
    c(180,   0,   0),  //  1 red → dark red
    c(  0, 110,  80),  //  2 green → dark teal
    c(130,  85,   0),  //  3 yellow → dark amber
    c(  0,  70, 180),  //  4 blue → deep blue
    c(120,   0, 150),  //  5 magenta → dark purple
    c(  0, 110, 140),  //  6 cyan → dark teal
    c( 55,  55,  55),  //  7 white → dark gray (was light — must be readable on white)
    c(100, 100, 100),  //  8 bright black → medium gray
    c(200,  20,  20),  //  9 bright red
    c(  0, 140, 100),  // 10 bright green
    c(160, 105,   0),  // 11 bright yellow → amber
    c(  0,  95, 210),  // 12 bright blue
    c(150,   0, 190),  // 13 bright magenta
    c(  0, 145, 170),  // 14 bright cyan
    c( 15,  15,  15),  // 15 bright white → near black (was near-white — must be readable on white)
  ]

  static let palette = darkPalette
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

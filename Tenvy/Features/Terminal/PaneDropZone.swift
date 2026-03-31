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

/// Which edge of a pane the cursor is closest to during a drag.
///
/// Divides the view into four triangular regions by drawing diagonals
/// from corner to corner. The drop zone is the edge nearest the cursor.
/// Ported from Ghostty's `TerminalSplitDropZone`.
enum PaneDropZone: String, Equatable {
  case top
  case bottom
  case left
  case right

  /// Determines which drop zone the cursor is in based on proximity to edges.
  static func calculate(at point: CGPoint, in size: CGSize) -> PaneDropZone {
    let relX = point.x / size.width
    let relY = point.y / size.height

    let distToLeft = relX
    let distToRight = 1 - relX
    let distToTop = relY
    let distToBottom = 1 - relY

    let minDist = min(distToLeft, distToRight, distToTop, distToBottom)

    if minDist == distToLeft { return .left }
    if minDist == distToRight { return .right }
    if minDist == distToTop { return .top }
    return .bottom
  }

  /// Maps drop zone to split direction for tree insertion.
  var splitDirection: SplitDirection {
    switch self {
    case .top: .up
    case .bottom: .down
    case .left: .left
    case .right: .right
    }
  }

  /// Colored overlay showing where the split will appear.
  @ViewBuilder
  func overlay(in size: CGSize) -> some View {
    let overlayColor = Color.accentColor.opacity(0.3)

    switch self {
    case .top:
      VStack(spacing: 0) {
        Rectangle()
          .fill(overlayColor)
          .frame(height: size.height / 2)
        Spacer()
      }
    case .bottom:
      VStack(spacing: 0) {
        Spacer()
        Rectangle()
          .fill(overlayColor)
          .frame(height: size.height / 2)
      }
    case .left:
      HStack(spacing: 0) {
        Rectangle()
          .fill(overlayColor)
          .frame(width: size.width / 2)
        Spacer()
      }
    case .right:
      HStack(spacing: 0) {
        Spacer()
        Rectangle()
          .fill(overlayColor)
          .frame(width: size.width / 2)
      }
    }
  }
}

#Preview("Drop Zone - Left") {
  PaneDropZone.left.overlay(in: CGSize(width: 400, height: 300))
    .frame(width: 400, height: 300)
}

#Preview("Drop Zone - Right") {
  PaneDropZone.right.overlay(in: CGSize(width: 400, height: 300))
    .frame(width: 400, height: 300)
}

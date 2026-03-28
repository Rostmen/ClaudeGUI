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

// MARK: - SplitViewDirection

/// Whether the two panes sit side-by-side (horizontal) or stacked (vertical).
/// Ported from Ghostty's SplitView.swift / SplitTree.swift.
enum SplitViewDirection: Codable {
  case horizontal  // left | right
  case vertical    // top / bottom
}

// MARK: - PaneSplitView

/// A two-pane split view with a draggable divider.
/// "left" = left pane for horizontal, top pane for vertical.
/// "right" = right pane for horizontal, bottom pane for vertical.
///
/// Ported from Ghostty's `SplitView` — uses GeometryReader + ZStack + offset
/// instead of NSSplitView so the pane content is never destroyed on resize.
struct PaneSplitView<L: View, R: View>: View {
  let direction: SplitViewDirection
  @Binding var split: CGFloat
  let left: L
  let right: R

  private let minSize: CGFloat = 10
  private let splitterVisibleSize: CGFloat = 1
  private let splitterInvisibleSize: CGFloat = 6

  init(
    _ direction: SplitViewDirection,
    _ split: Binding<CGFloat>,
    @ViewBuilder left: () -> L,
    @ViewBuilder right: () -> R
  ) {
    self.direction = direction
    self._split = split
    self.left = left()
    self.right = right()
  }

  var body: some View {
    GeometryReader { geo in
      let leftRect = leftRect(for: geo.size)
      let rightRect = rightRect(for: geo.size, leftRect: leftRect)
      let splitterPt = splitterPoint(for: geo.size, leftRect: leftRect)

      ZStack(alignment: .topLeading) {
        left
          .frame(width: leftRect.size.width, height: leftRect.size.height)
          .offset(x: leftRect.origin.x, y: leftRect.origin.y)
          .accessibilityElement(children: .contain)
          .accessibilityLabel(direction == .horizontal ? "Left pane" : "Top pane")

        right
          .frame(width: rightRect.size.width, height: rightRect.size.height)
          .offset(x: rightRect.origin.x, y: rightRect.origin.y)
          .accessibilityElement(children: .contain)
          .accessibilityLabel(direction == .horizontal ? "Right pane" : "Bottom pane")

        PaneSplitDivider(
          direction: direction,
          split: $split,
          visibleSize: splitterVisibleSize,
          invisibleSize: splitterInvisibleSize
        )
        .position(splitterPt)
        .gesture(dragGesture(geo.size))
      }
    }
  }

  private func dragGesture(_ size: CGSize) -> some Gesture {
    DragGesture().onChanged { gesture in
      switch direction {
      case .horizontal:
        let new = min(max(minSize, gesture.location.x), size.width - minSize)
        split = new / size.width
      case .vertical:
        let new = min(max(minSize, gesture.location.y), size.height - minSize)
        split = new / size.height
      }
    }
  }

  private func leftRect(for size: CGSize) -> CGRect {
    var result = CGRect(origin: .zero, size: size)
    switch direction {
    case .horizontal:
      result.size.width = size.width * split - splitterVisibleSize / 2
    case .vertical:
      result.size.height = size.height * split - splitterVisibleSize / 2
    }
    return result
  }

  private func rightRect(for size: CGSize, leftRect: CGRect) -> CGRect {
    var result = CGRect(origin: .zero, size: size)
    switch direction {
    case .horizontal:
      result.origin.x = leftRect.size.width + splitterVisibleSize / 2
      result.size.width = size.width - result.origin.x
    case .vertical:
      result.origin.y = leftRect.size.height + splitterVisibleSize / 2
      result.size.height = size.height - result.origin.y
    }
    return result
  }

  private func splitterPoint(for size: CGSize, leftRect: CGRect) -> CGPoint {
    switch direction {
    case .horizontal: return CGPoint(x: leftRect.size.width, y: size.height / 2)
    case .vertical:   return CGPoint(x: size.width / 2,     y: leftRect.size.height)
    }
  }
}

// MARK: - PaneSplitDivider

/// The thin draggable divider bar rendered between the two panes.
struct PaneSplitDivider: View {
  let direction: SplitViewDirection
  @Binding var split: CGFloat
  let visibleSize: CGFloat
  let invisibleSize: CGFloat

  var body: some View {
    ZStack {
      // Invisible hit-test area (wider than the visible bar)
      Color.clear
        .frame(width: invisibleWidth, height: invisibleHeight)
        .contentShape(Rectangle())
      // Visible bar
      Rectangle()
        .fill(Color(nsColor: .separatorColor))
        .frame(width: visibleWidth, height: visibleHeight)
    }
    .pointerStyle(direction == .horizontal ? .frameResize(position: .trailing) : .frameResize(position: .top))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(direction == .horizontal ? "Horizontal split divider" : "Vertical split divider")
    .accessibilityValue("\(Int(split * 100))%")
    .accessibilityHint(direction == .horizontal
      ? "Drag to resize the left and right panes"
      : "Drag to resize the top and bottom panes")
    .accessibilityAddTraits(.isButton)
    .accessibilityAdjustableAction { dir in
      let step: CGFloat = 0.025
      switch dir {
      case .increment: split = min(split + step, 0.9)
      case .decrement: split = max(split - step, 0.1)
      @unknown default: break
      }
    }
  }

  private var visibleWidth:   CGFloat? { direction == .horizontal ? visibleSize : nil }
  private var visibleHeight:  CGFloat? { direction == .vertical   ? visibleSize : nil }
  private var invisibleWidth: CGFloat? { direction == .horizontal ? visibleSize + invisibleSize : nil }
  private var invisibleHeight: CGFloat? { direction == .vertical   ? visibleSize + invisibleSize : nil }
}

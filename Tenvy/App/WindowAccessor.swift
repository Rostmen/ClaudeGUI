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
import SwiftUI

// MARK: - Window Accessor

/// Bridges SwiftUI's view hierarchy to the underlying NSWindow.
/// Used to capture the window reference and apply custom styling.
struct WindowAccessor: NSViewRepresentable {
  @Binding var window: NSWindow?

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        self.window = window
        applyWindowStyle(window)
        // Window delegate is assigned by AppDelegate.applicationDidFinishLaunching
        // and AppDelegate.handleWindowBecameKey — no assignment needed here.
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      if let window = nsView.window, window != self.window {
        self.window = window
        applyWindowStyle(window)
        // handleWindowBecameKey ensures the new window gets the delegate.
      }
    }
  }

  private func applyWindowStyle(_ window: NSWindow) {
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .visible
    window.styleMask.insert(.fullSizeContentView)
    window.isOpaque = false
    window.backgroundColor = .clear
  }
}

// MARK: - NSWindow Session ID Extension

private var sessionIdKey: UInt8 = 0

extension NSWindow {
  /// Store session ID directly on the window using associated objects.
  /// Provides a fallback when the registry doesn't have the mapping.
  var sessionId: String? {
    get { objc_getAssociatedObject(self, &sessionIdKey) as? String }
    set { objc_setAssociatedObject(self, &sessionIdKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
  }
}

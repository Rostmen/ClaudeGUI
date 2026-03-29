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

/// Actions emitted by terminal views (both Claude sessions and plain terminals).
/// Handled by `ContentViewModel.handleTerminalAction(_:for:)`.
enum TerminalAction {
  /// Terminal surface gained keyboard focus.
  case focusGained

  /// User requested a split from Ghostty's context menu.
  case splitRequested(direction: SplitDirection)

  /// Process state changed (CPU, memory, PID) — Claude sessions only.
  case stateChanged(info: SessionMonitorInfo)

  /// Shell process started with the given PID — Claude sessions only.
  case shellStarted(pid: pid_t)

  /// Claude session activated in the terminal — triggers hook tracking.
  case sessionActivated(id: String)

  /// Terminal input proxy is ready for registration (permission responses, restart).
  case inputReady(proxy: GhosttyInputProxy, sessionId: String)

  /// Terminal input should be unregistered (terminal closing).
  case inputUnregistered(sessionId: String)
}

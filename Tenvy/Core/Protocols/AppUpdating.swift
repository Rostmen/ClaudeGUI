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

/// Checks GitHub for new releases and drives silent Homebrew updates
@MainActor
protocol AppUpdating: AnyObject {
  /// True when a newer version is available
  var updateAvailable: Bool { get }

  /// The latest version string from GitHub (e.g. "1.2.3"), or nil if not yet checked
  var latestVersion: String? { get }

  /// True when the update prompt overlay should be shown
  var shouldShowPrompt: Bool { get set }

  /// True while a brew install is in progress — suppresses quit confirmation dialogs
  var isUpdating: Bool { get }

  /// Current installation state machine value
  var updateState: UpdateState { get set }

  /// Fetch the latest GitHub release and compare with the running version
  func checkForUpdates()

  /// Start a silent `brew install --cask --force` and relaunch on success
  func performUpdate()

  /// Fetch the release notes body for a specific version, or nil on failure
  func fetchReleaseNotes(for version: String) async -> String?
}

// MARK: - Conformance

extension UpdateService: AppUpdating {}

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
import Foundation

private struct GitHubRelease: Decodable {
  let tagName: String
  let name: String
  let htmlURL: String
  let body: String?

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case name
    case htmlURL = "html_url"
    case body
  }
}

enum UpdateState: Equatable {
  case idle
  case installing
  case success
  case failed(String)
}

/// Handles update checking against the GitHub releases API
@Observable
@MainActor
final class UpdateService {

  var updateAvailable: Bool = false
  var latestVersion: String?
  var releaseURL: URL?
  var shouldShowPrompt: Bool = false
  /// Set to true when an update is in progress — suppresses quit confirmation dialogs
  var isUpdating: Bool = false
  var updateState: UpdateState = .idle

  private let apiURL = URL(string: "https://api.github.com/repos/Rostmen/ClaudeGUI/releases/latest")!

  init() {}

  /// Fetches the latest release from GitHub and compares with the current app version.
  func checkForUpdates() {
    Task {
      guard let release = await fetchLatestRelease() else { return }
      let remoteVersion = release.tagName.hasPrefix("v")
        ? String(release.tagName.dropFirst())
        : release.tagName

      let currentVersion = AppInfo.version

      if isVersion(remoteVersion, newerThan: currentVersion) {
        updateAvailable = true
        latestVersion = remoteVersion
        releaseURL = URL(string: release.htmlURL)
        shouldShowPrompt = true
      }
    }
  }

  /// Fetches the release notes body for a specific version tag.
  /// Returns nil if the network request fails or there is no body.
  func fetchReleaseNotes(for version: String) async -> String? {
    guard let release = await fetchLatestRelease() else { return nil }
    let remoteVersion = release.tagName.hasPrefix("v")
      ? String(release.tagName.dropFirst())
      : release.tagName
    guard remoteVersion == version else { return nil }
    return release.body
  }

  /// Installs the latest version silently in the background, then relaunches the app.
  /// Falls back to opening the GitHub release page if Homebrew is not found.
  func performUpdate() {
    let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    guard let brewPath = brewPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
      if let url = releaseURL { NSWorkspace.shared.open(url) }
      shouldShowPrompt = false
      return
    }

    isUpdating = true
    updateState = .installing

    Task { [weak self] in
      let result = await Self.runBrew(brewPath: brewPath)
      if result == 0 {
        self?.updateState = .success
        // Brief pause so user sees "Restarting…", then relaunch.
        // We spawn a background shell that waits for this process to fully exit
        // before opening the new app — avoids the race between open() and terminate().
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
          let pid = ProcessInfo.processInfo.processIdentifier
          let task = Process()
          task.executableURL = URL(fileURLWithPath: "/bin/sh")
          task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open /Applications/Tenvy.app"]
          try? task.run()
          NSApplication.shared.terminate(nil)
        }
      } else {
        self?.isUpdating = false
        self?.updateState = .failed("brew exited with code \(result). Try running manually in Terminal.")
      }
    }
  }

  private static func runBrew(brewPath: String) async -> Int32 {
    await withCheckedContinuation { continuation in
      let task = Process()
      task.executableURL = URL(fileURLWithPath: brewPath)
      task.arguments = ["install", "--cask", "--force", "rostmen/tenvy/tenvy"]
      task.standardOutput = FileHandle.nullDevice
      task.standardError = FileHandle.nullDevice
      task.terminationHandler = { process in
        continuation.resume(returning: process.terminationStatus)
      }
      do {
        try task.run()
      } catch {
        continuation.resume(returning: -1)
      }
    }
  }

  // MARK: - Private helpers

  private func fetchLatestRelease() async -> GitHubRelease? {
    var request = URLRequest(url: apiURL)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    do {
      let (data, _) = try await URLSession.shared.data(for: request)
      return try JSONDecoder().decode(GitHubRelease.self, from: data)
    } catch {
      return nil
    }
  }

  /// Returns true when `newer` is a higher semantic version than `current`.
  /// Compares dot-separated integer components left to right.
  private func isVersion(_ newer: String, newerThan current: String) -> Bool {
    let newerParts = newer.split(separator: ".").compactMap { Int($0) }
    let currentParts = current.split(separator: ".").compactMap { Int($0) }
    let count = max(newerParts.count, currentParts.count)
    for i in 0..<count {
      let n = i < newerParts.count ? newerParts[i] : 0
      let c = i < currentParts.count ? currentParts[i] : 0
      if n != c { return n > c }
    }
    return false
  }
}

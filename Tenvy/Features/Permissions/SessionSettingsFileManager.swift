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

/// Manages per-session settings files written to Application Support.
///
/// Each active Claude session with custom permissions gets a settings file at:
/// `~/Library/Application Support/Tenvy/session-settings/<terminalId>.json`
///
/// The file is passed to Claude CLI via `--settings` at launch and cleaned up
/// when the session is deactivated.
struct SessionSettingsFileManager {

  /// Base directory: `~/Library/Application Support/Tenvy/session-settings/`
  static var baseDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("Tenvy")
      .appendingPathComponent("session-settings")
  }

  /// Write a settings file for a session. Returns the file path string for the `--settings` flag.
  @discardableResult
  static func writeSettingsFile(terminalId: String, settings: ClaudePermissionSettings) throws -> String {
    let dir = baseDirectory
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let fileURL = dir.appendingPathComponent("\(terminalId).json")

    // Build the settings JSON that Claude CLI expects
    var settingsDict: [String: Any] = [:]
    settingsDict["defaultMode"] = settings.permissionMode.rawValue

    let permissionsData = try JSONEncoder().encode(settings.permissions)
    let permissionsObj = try JSONSerialization.jsonObject(with: permissionsData)
    settingsDict["permissions"] = permissionsObj

    let output = try JSONSerialization.data(
      withJSONObject: settingsDict,
      options: [.prettyPrinted, .sortedKeys]
    )
    try output.write(to: fileURL)

    return fileURL.path
  }

  /// Remove the settings file for a session.
  static func removeSettingsFile(terminalId: String) {
    let fileURL = baseDirectory.appendingPathComponent("\(terminalId).json")
    try? FileManager.default.removeItem(at: fileURL)
  }

  /// Remove all session settings files (app cleanup).
  static func removeAllSettingsFiles() {
    try? FileManager.default.removeItem(at: baseDirectory)
  }
}

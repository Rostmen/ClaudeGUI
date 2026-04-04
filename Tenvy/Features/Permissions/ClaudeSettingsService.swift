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

/// Reads and writes Claude Code permission settings from `~/.claude/settings.json`
/// and project-level `.claude/settings.json` files.
///
/// All read/write methods preserve other top-level keys in the JSON file
/// (hooks, plugins, etc.) — only the `permissions` and `defaultMode` keys are modified.
struct ClaudeSettingsService {

  /// The global settings file: `~/.claude/settings.json`
  static var globalSettingsURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude")
      .appendingPathComponent("settings.json")
  }

  /// Project-level settings file: `<projectPath>/.claude/settings.json`
  static func projectSettingsURL(for projectPath: String) -> URL? {
    let url = URL(fileURLWithPath: projectPath)
      .appendingPathComponent(".claude")
      .appendingPathComponent("settings.json")
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  // MARK: - Read

  /// Read the permissions block from a settings file.
  static func readPermissions(from url: URL) -> ClaudePermissions {
    guard let raw = loadRawSettings(from: url),
          let permissionsRaw = raw["permissions"],
          let permissionsData = try? JSONSerialization.data(withJSONObject: permissionsRaw),
          let decoded = try? JSONDecoder().decode(ClaudePermissions.self, from: permissionsData)
    else { return .empty }
    return decoded
  }

  /// Read the permission mode from a settings file.
  static func readPermissionMode(from url: URL) -> ClaudePermissionMode? {
    guard let raw = loadRawSettings(from: url),
          let modeString = raw["defaultMode"] as? String
    else { return nil }
    return ClaudePermissionMode(rawValue: modeString)
  }

  /// Read the full permission settings (mode + permissions) from a settings file.
  static func readPermissionSettings(from url: URL) -> ClaudePermissionSettings {
    ClaudePermissionSettings(
      permissionMode: readPermissionMode(from: url) ?? .default,
      permissions: readPermissions(from: url)
    )
  }

  // MARK: - Write

  /// Write permissions to a settings file, preserving other keys (hooks, plugins, etc.)
  static func writePermissions(_ permissions: ClaudePermissions, to url: URL) throws {
    var raw = loadRawSettings(from: url) ?? [:]
    let encoded = try JSONEncoder().encode(permissions)
    let obj = try JSONSerialization.jsonObject(with: encoded)
    raw["permissions"] = obj
    try writeRawSettings(raw, to: url)
  }

  /// Write the permission mode to a settings file, preserving other keys.
  static func writePermissionMode(_ mode: ClaudePermissionMode, to url: URL) throws {
    var raw = loadRawSettings(from: url) ?? [:]
    raw["defaultMode"] = mode.rawValue
    try writeRawSettings(raw, to: url)
  }

  /// Write full permission settings (mode + permissions) to a settings file.
  static func writePermissionSettings(_ settings: ClaudePermissionSettings, to url: URL) throws {
    var raw = loadRawSettings(from: url) ?? [:]
    let encoded = try JSONEncoder().encode(settings.permissions)
    let obj = try JSONSerialization.jsonObject(with: encoded)
    raw["permissions"] = obj
    raw["defaultMode"] = settings.permissionMode.rawValue
    try writeRawSettings(raw, to: url)
  }

  // MARK: - Merge

  /// Merge global + project permissions for a new session.
  /// Global provides the base; project rules are appended (deduped by exact string match).
  /// Permission mode comes from global settings only (project settings don't set mode).
  static func mergeForNewSession(projectPath: String) -> ClaudePermissionSettings {
    let globalPerms = readPermissions(from: globalSettingsURL)
    let globalMode = readPermissionMode(from: globalSettingsURL) ?? .default

    guard let projectURL = projectSettingsURL(for: projectPath) else {
      return ClaudePermissionSettings(permissionMode: globalMode, permissions: globalPerms)
    }

    let projectPerms = readPermissions(from: projectURL)

    let merged = ClaudePermissions(
      allow: mergeRules(globalPerms.allow, projectPerms.allow),
      deny: mergeRules(globalPerms.deny, projectPerms.deny),
      ask: mergeRules(globalPerms.ask, projectPerms.ask)
    )

    return ClaudePermissionSettings(permissionMode: globalMode, permissions: merged)
  }

  // MARK: - Private

  private static func loadRawSettings(from url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url),
          let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return raw
  }

  private static func writeRawSettings(_ raw: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let output = try JSONSerialization.data(
      withJSONObject: raw,
      options: [.prettyPrinted, .sortedKeys]
    )
    try output.write(to: url)
  }

  /// Merge two rule arrays, deduplicating by exact string match.
  private static func mergeRules(_ base: [String], _ overlay: [String]) -> [String] {
    var seen = Set(base)
    var result = base
    for rule in overlay where !seen.contains(rule) {
      seen.insert(rule)
      result.append(rule)
    }
    return result
  }
}

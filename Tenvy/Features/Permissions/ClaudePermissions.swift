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
import CryptoKit

/// Permission mode Claude Code operates under.
enum ClaudePermissionMode: String, Codable, CaseIterable, Identifiable {
  case `default`
  case acceptEdits
  case plan
  case auto
  case bypassPermissions

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .default: "Default"
    case .acceptEdits: "Accept Edits"
    case .plan: "Plan (Read-Only)"
    case .auto: "Auto"
    case .bypassPermissions: "Bypass Permissions"
    }
  }

  var description: String {
    switch self {
    case .default: "Prompts for permission on first use of each tool"
    case .acceptEdits: "Auto-accepts file edits (except protected dirs)"
    case .plan: "Read-only: can analyze but not modify"
    case .auto: "Auto-approves with background safety checks"
    case .bypassPermissions: "Skips all prompts (except protected dirs)"
    }
  }
}

/// The permissions section of a Claude settings file.
/// Contains allow/deny/ask rule arrays for granular tool control.
struct ClaudePermissions: Codable, Equatable {
  var allow: [String] = []
  var deny: [String] = []
  var ask: [String] = []

  static let empty = ClaudePermissions()

  var isEmpty: Bool {
    allow.isEmpty && deny.isEmpty && ask.isEmpty
  }
}

/// Full per-session permission payload stored in GRDB and written to temp settings files.
struct ClaudePermissionSettings: Codable, Equatable {
  var permissionMode: ClaudePermissionMode = .default
  var permissions: ClaudePermissions = .empty

  static let empty = ClaudePermissionSettings()

  /// Deterministic SHA-256 hash of the settings content.
  /// Uses sorted-keys JSON encoding so the hash is stable regardless of property order.
  var contentHash: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(self) else { return "" }
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

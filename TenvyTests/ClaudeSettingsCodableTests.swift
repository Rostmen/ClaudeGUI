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
import Testing
@testable import Tenvy

/// Tests for the `ClaudeHookGroup` / `ClaudeHookCommand` Codable structs used
/// by `HookInstallationService` to read and write `~/.claude/settings.json`.
///
/// All tests are pure — no filesystem access.
@MainActor
struct ClaudeSettingsCodableTests {

  @Test("ClaudeHookCommand round-trips through JSON")
  func hookCommandRoundTrip() throws {
    let command = ClaudeHookCommand(type: "command", command: "~/.claude/hooks/chat-sessions-hook.sh")
    let data = try JSONEncoder().encode(command)
    let decoded = try JSONDecoder().decode(ClaudeHookCommand.self, from: data)

    #expect(decoded.type == command.type)
    #expect(decoded.command == command.command)
  }

  @Test("ClaudeHookGroup round-trips through JSON")
  func hookGroupRoundTrip() throws {
    let group = ClaudeHookGroup(hooks: [
      ClaudeHookCommand(type: "command", command: "~/.claude/hooks/chat-sessions-hook.sh")
    ])
    let data = try JSONEncoder().encode(group)
    let decoded = try JSONDecoder().decode(ClaudeHookGroup.self, from: data)

    #expect(decoded.hooks.count == 1)
    #expect(decoded.hooks[0].command == group.hooks[0].command)
  }

  @Test("Hooks dictionary round-trips through JSON")
  func hooksDictionaryRoundTrip() throws {
    let hooks: [String: [ClaudeHookGroup]] = [
      "Stop": [ClaudeHookGroup(hooks: [ClaudeHookCommand(type: "command", command: "~/.claude/hooks/chat-sessions-hook.sh")])]
    ]
    let data = try JSONEncoder().encode(hooks)
    let decoded = try JSONDecoder().decode([String: [ClaudeHookGroup]].self, from: data)

    #expect(decoded["Stop"]?.count == 1)
    #expect(decoded["Stop"]?.first?.hooks.first?.command.contains("chat-sessions-hook.sh") == true)
  }

  @Test("Claude settings JSON with hooks decodes correctly")
  func realWorldSettingsJSON() throws {
    // Mirrors a real ~/.claude/settings.json hooks subtree
    let json = """
    {
      "Stop": [
        {"hooks": [{"type": "command", "command": "~/.claude/hooks/chat-sessions-hook.sh"}]}
      ],
      "UserPromptSubmit": [
        {"hooks": [{"type": "command", "command": "~/.claude/hooks/chat-sessions-hook.sh"}]}
      ]
    }
    """
    let data = try #require(json.data(using: .utf8))
    let decoded = try JSONDecoder().decode([String: [ClaudeHookGroup]].self, from: data)

    #expect(decoded["Stop"]?.count == 1)
    #expect(decoded["UserPromptSubmit"]?.count == 1)

    let stopCommand = decoded["Stop"]?.first?.hooks.first?.command ?? ""
    #expect(stopCommand.contains("chat-sessions-hook.sh"))
  }

  @Test("Hook detection logic correctly identifies managed hook")
  func hookDetectionLogic() throws {
    let hooks: [String: [ClaudeHookGroup]] = [
      "Stop": [ClaudeHookGroup(hooks: [
        ClaudeHookCommand(type: "command", command: "~/.claude/hooks/chat-sessions-hook.sh")
      ])]
    ]

    let isInstalled = hooks["Stop"]?
      .flatMap(\.hooks)
      .contains { $0.command.contains("chat-sessions-hook.sh") } ?? false

    #expect(isInstalled == true)
  }

  @Test("Hook detection returns false when no matching command")
  func hookDetectionNegative() throws {
    let hooks: [String: [ClaudeHookGroup]] = [
      "Stop": [ClaudeHookGroup(hooks: [
        ClaudeHookCommand(type: "command", command: "/some/other/script.sh")
      ])]
    ]

    let isInstalled = hooks["Stop"]?
      .flatMap(\.hooks)
      .contains { $0.command.contains("chat-sessions-hook.sh") } ?? false

    #expect(isInstalled == false)
  }
}

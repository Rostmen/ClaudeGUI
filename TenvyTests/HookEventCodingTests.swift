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

/// Tests for `HookEvent` and `ToolInput` Codable conformance.
///
/// The JSON uses snake_case keys; Swift properties use camelCase.
/// CodingKeys must map them correctly in both directions.
struct HookEventCodingTests {

  @Test("HookEvent decodes snake_case JSON keys to camelCase properties")
  func hookEventDecoding() throws {
    let json = """
    {
      "session_id": "abc-123",
      "event": "PreToolUse",
      "state": "thinking",
      "cwd": "/Users/dev/myproject",
      "tool": "Bash",
      "message": null,
      "tool_input": {
        "command": "ls -la",
        "file_path": null,
        "content": null
      },
      "timestamp": "2026-01-01T00:00:00Z"
    }
    """
    let data = try #require(json.data(using: .utf8))
    let event = try JSONDecoder().decode(HookEvent.self, from: data)

    #expect(event.sessionId == "abc-123")
    #expect(event.event == "PreToolUse")
    #expect(event.state == "thinking")
    #expect(event.cwd == "/Users/dev/myproject")
    #expect(event.tool == "Bash")
    #expect(event.toolInput?.command == "ls -la")
    #expect(event.toolInput?.filePath == nil)
    #expect(event.timestamp == "2026-01-01T00:00:00Z")
  }

  @Test("ToolInput decodes file_path to filePath")
  func toolInputFilePathDecoding() throws {
    let json = """
    {"command": null, "file_path": "/tmp/foo.txt", "content": "hello"}
    """
    let data = try #require(json.data(using: .utf8))
    let input = try JSONDecoder().decode(ToolInput.self, from: data)

    #expect(input.command == nil)
    #expect(input.filePath == "/tmp/foo.txt")
    #expect(input.content == "hello")
  }

  @Test("HookEvent encodes camelCase properties back to snake_case JSON keys")
  func hookEventRoundTrip() throws {
    let json = """
    {
      "session_id": "xyz",
      "event": "Stop",
      "state": "waiting",
      "timestamp": "2026-06-01T12:00:00Z"
    }
    """
    let data = try #require(json.data(using: .utf8))
    let event = try JSONDecoder().decode(HookEvent.self, from: data)
    let reEncoded = try JSONEncoder().encode(event)
    let reDecoded = try JSONDecoder().decode(HookEvent.self, from: reEncoded)

    #expect(reDecoded.sessionId == event.sessionId)
    #expect(reDecoded.event == event.event)
    #expect(reDecoded.state == event.state)
  }

  @Test("HookEvent.date parses ISO8601 timestamp")
  func hookEventDateParsing() throws {
    let json = """
    {"session_id":"s","event":"Stop","state":"waiting","timestamp":"2026-03-15T10:30:00Z"}
    """
    let data = try #require(json.data(using: .utf8))
    let event = try JSONDecoder().decode(HookEvent.self, from: data)

    let date = try #require(event.date)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    #expect(cal.component(.year, from: date) == 2026)
    #expect(cal.component(.month, from: date) == 3)
    #expect(cal.component(.day, from: date) == 15)
  }
}

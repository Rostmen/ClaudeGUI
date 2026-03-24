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

/// Tests for `ProcessPoller.parsePs` — the pure parser that converts raw `ps`
/// output into a dictionary of `ProcessRecord` values.
///
/// Because `parsePs` is a pure static function it is trivially unit-testable
/// without spawning any subprocesses.
struct ProcessPollerTests {

  @Test("parsePs correctly parses a well-formed ps line")
  func parseSingleLine() {
    let output = """
    PID  PPID %CPU   RSS ARGS
     42    10  3.5  4096 /usr/bin/claude --resume abc123
    """
    let records = ProcessPoller.parsePs(output: output)

    let record = try! #require(records[42])
    #expect(record.pid == 42)
    #expect(record.ppid == 10)
    #expect(record.cpu == 3.5)
    #expect(record.memoryKB == 4096)
    #expect(record.args.contains("claude"))
  }

  @Test("parsePs parses multiple lines into separate records")
  func parseMultipleLines() {
    let output = """
    PID  PPID %CPU   RSS ARGS
      1     0  0.0   512 /sbin/launchd
    100    50 15.0  2048 /usr/bin/node server.js
    200   100  0.1   256 /bin/zsh
    """
    let records = ProcessPoller.parsePs(output: output)

    #expect(records.count == 3)
    #expect(records[1] != nil)
    #expect(records[100] != nil)
    #expect(records[200] != nil)
    #expect(records[100]?.cpu == 15.0)
  }

  @Test("parsePs skips malformed lines without crashing")
  func parseMalformedLines() {
    let output = """
    PID  PPID %CPU   RSS ARGS
    not-a-pid 10 0.0 100 /foo
     99    10  1.0  512 /usr/bin/python3
    """
    let records = ProcessPoller.parsePs(output: output)
    // Only the valid line should parse
    #expect(records.count == 1)
    #expect(records[99] != nil)
  }

  @Test("parsePs handles empty output gracefully")
  func parseEmptyOutput() {
    let records = ProcessPoller.parsePs(output: "")
    #expect(records.isEmpty)
  }

  @Test("parsePs handles header-only output")
  func parseHeaderOnly() {
    let output = "PID  PPID %CPU   RSS ARGS\n"
    let records = ProcessPoller.parsePs(output: output)
    #expect(records.isEmpty)
  }

  @Test("parsePs captures multi-word args as a single string")
  func parseMultiWordArgs() {
    let output = """
    PID  PPID %CPU  RSS ARGS
     55    10  0.0  128 /bin/sh -c exec claude --resume some-id
    """
    let records = ProcessPoller.parsePs(output: output)
    let record = try! #require(records[55])
    #expect(record.args.contains("claude"))
    #expect(record.args.contains("--resume"))
  }
}

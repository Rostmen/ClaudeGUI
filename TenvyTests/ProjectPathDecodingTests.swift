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


/// Tests for the path-decoding logic extracted from `SessionManager`.
///
/// The algorithm is not currently exposed as a public/internal function, so
/// we test its behaviour through a standalone pure function that mirrors the
/// production code.  This allows us to cover edge cases without spinning up a
/// full `SessionManager`.
struct ProjectPathDecodingTests {

  // MARK: - Helpers (mirrors SessionManager.decodeProjectPath logic)

  private func naiveDecode(_ encoded: String) -> String {
    "/" + encoded
      .replacingOccurrences(of: "-", with: "/")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  // MARK: - Tests

  @Test("Naive decode produces correct path for simple paths")
  func naiveDecodeSimple() {
    // "-Users-alice-Documents" → "/Users/alice/Documents"
    let encoded = "-Users-alice-Documents"
    let result = naiveDecode(encoded)
    #expect(result == "/Users/alice/Documents")
  }

  @Test("Naive decode handles root-level paths")
  func naiveDecodeRoot() {
    // "-tmp" → "/tmp"
    #expect(naiveDecode("-tmp") == "/tmp")
  }

  @Test("Naive decode strips leading slash from result correctly")
  func naiveDecodeNoDoubleSlash() {
    let result = naiveDecode("-Users-bob-repos")
    #expect(!result.hasPrefix("//"))
    #expect(result.hasPrefix("/"))
  }

  @Test("Naive decode produces wrong path when component contains hyphen")
  func naiveDecodeHyphenInComponent() {
    // "-Users-alice-my-app" naively decodes to "/Users/alice/my/app" (wrong)
    let encoded = "-Users-alice-my-app"
    let naive = naiveDecode(encoded)
    // The naive result treats every '-' as '/', which is wrong for "my-app"
    #expect(naive == "/Users/alice/my/app")  // demonstrates the known limitation
    // The real path would be "/Users/alice/my-app"
  }
}

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

struct GitChangedFile: Identifiable, Hashable {
  let id = UUID()
  let path: String
  let name: String
  let isDirectory: Bool
  let status: GitFileStatus?
  let diff: String?
  var children: [GitChangedFile]?

  // Convenience initializer for files
  init(path: String, name: String, status: GitFileStatus, diff: String) {
    self.path = path
    self.name = name
    self.isDirectory = false
    self.status = status
    self.diff = diff
    self.children = nil
  }

  // Convenience initializer for directories
  init(path: String, name: String, children: [GitChangedFile]) {
    self.path = path
    self.name = name
    self.isDirectory = true
    self.status = nil
    self.diff = nil
    self.children = children
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(path)
  }

  static func == (lhs: GitChangedFile, rhs: GitChangedFile) -> Bool {
    lhs.path == rhs.path
  }
}

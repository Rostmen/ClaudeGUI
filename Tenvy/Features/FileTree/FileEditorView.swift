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

import SwiftUI
import CodeEditSourceEditor
import CodeEditLanguages

struct FileEditorView: View {
  let filePath: String
  @State private var text: String = ""
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var sourceState: SourceEditorState = .init()
  var body: some View {
    ZStack {
      if isLoading {
        ProgressView("Loading...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = errorMessage {
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 32))
            .foregroundColor(.orange)
          Text("Error loading file")
            .font(.headline)
          Text(error)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        SourceEditor(
          $text,
          language: language,
          configuration: SourceEditorConfiguration(
            appearance: .init(
              theme: EditorTheme.dark,
              font: .monospacedSystemFont(ofSize: 13, weight: .regular),
              wrapLines: true
            ),
            behavior: .init(
              indentOption: .spaces(count: 2)
            )
          ),
          state: $sourceState
        )
      }
    }
    .task {
      await loadFile()
    }
    .onChange(of: filePath) { _, _ in
      Task {
        await loadFile()
      }
    }
  }

  private var language: CodeLanguage {
    let ext = (filePath as NSString).pathExtension.lowercased()
    switch ext {
    case "swift":
      return .swift
    case "js":
      return .javascript
    case "ts":
      return .typescript
    case "jsx":
      return .jsx
    case "tsx":
      return .tsx
    case "json":
      return .json
    case "md", "markdown":
      return .markdown
    case "py":
      return .python
    case "rb":
      return .ruby
    case "go":
      return .go
    case "rs":
      return .rust
    case "html":
      return .html
    case "css":
      return .css
    case "yaml", "yml":
      return .yaml
    case "sh", "bash", "zsh":
      return .bash
    case "c":
      return .c
    case "cpp", "cc", "cxx":
      return .cpp
    case "h", "hpp":
      return .objc
    case "m":
      return .objc
    case "java":
      return .java
    case "kt":
      return .kotlin
    case "sql":
      return .sql
    default:
      return .default
    }
  }

  private func loadFile() async {
    isLoading = true
    errorMessage = nil

    do {
      let fileURL = URL(fileURLWithPath: filePath)
      let content = try String(contentsOf: fileURL, encoding: .utf8)
      await MainActor.run {
        text = content
        isLoading = false
      }
    } catch {
      await MainActor.run {
        errorMessage = error.localizedDescription
        isLoading = false
      }
    }
  }
}

// MARK: - Editor Theme

extension EditorTheme {
  static let dark = EditorTheme(
    text: .init(color: .init(hex: "#EAEAEA")),
    insertionPoint: .init(hex: "#EAEAEA"),
    invisibles: .init(color: .init(hex: "#3B3B4F")),
    background: .init(hex: "#1E1E2E"),  // Dark background, can't use .clear due to MinimapView
    lineHighlight: .init(hex: "#2A2A3E"),
    selection: .init(hex: "#3B3B4F"),
    keywords: .init(color: .init(hex: "#FC5FA3")),
    commands: .init(color: .init(hex: "#78C2B3")),
    types: .init(color: .init(hex: "#D0A8FF")),
    attributes: .init(color: .init(hex: "#CC9768")),
    variables: .init(color: .init(hex: "#EAEAEA")),
    values: .init(color: .init(hex: "#D0BF69")),
    numbers: .init(color: .init(hex: "#D0BF69")),
    strings: .init(color: .init(hex: "#FC6A5D")),
    characters: .init(color: .init(hex: "#D0BF69")),
    comments: .init(color: .init(hex: "#6C7986"))
  )
}

// MARK: - Color Extension

private extension NSColor {
  convenience init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let r, g, b: UInt64
    switch hex.count {
    case 6:
      (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
    default:
      (r, g, b) = (0, 0, 0)
    }
    self.init(
      red: CGFloat(r) / 255,
      green: CGFloat(g) / 255,
      blue: CGFloat(b) / 255,
      alpha: 1
    )
  }
}

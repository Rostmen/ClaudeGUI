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
import CodeEditor

/// Sheet view for editing permission settings as raw JSON.
struct RawPermissionsEditorView: View {
  @Binding var settings: ClaudePermissionSettings
  @Environment(\.dismiss) private var dismiss
  @State private var jsonSource: String = ""
  @State private var parseError: String?

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Raw JSON Editor")
          .font(.headline)
        Spacer()
        if let error = parseError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      CodeEditor(source: $jsonSource, language: .json, theme: .ocean)
        .frame(minHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 6))

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)

        Spacer()

        Button("Apply") { applyChanges() }
          .keyboardShortcut(.defaultAction)
          .disabled(parseError != nil)
      }
    }
    .padding()
    .frame(minWidth: 500, minHeight: 400)
    .onAppear { jsonSource = encodeSettings() }
    .onChange(of: jsonSource) { _, newValue in validateJSON(newValue) }
  }

  private func encodeSettings() -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(settings),
          let string = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return string
  }

  private func validateJSON(_ json: String) {
    guard let data = json.data(using: .utf8) else {
      parseError = "Invalid encoding"
      return
    }
    do {
      _ = try JSONDecoder().decode(ClaudePermissionSettings.self, from: data)
      parseError = nil
    } catch {
      parseError = "Invalid JSON"
    }
  }

  private func applyChanges() {
    guard let data = jsonSource.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(ClaudePermissionSettings.self, from: data) else {
      return
    }
    settings = decoded
    dismiss()
  }
}

#Preview {
  @Previewable @State var settings = ClaudePermissionSettings(
    permissionMode: .default,
    permissions: ClaudePermissions(
      allow: ["Edit", "Bash(git *)"],
      deny: ["Bash(rm *)"],
      ask: ["Write"]
    )
  )
  RawPermissionsEditorView(settings: $settings)
}

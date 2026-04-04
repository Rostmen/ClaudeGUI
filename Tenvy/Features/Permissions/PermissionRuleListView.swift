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

/// A list of permission rules (allow/deny/ask) with add and remove functionality.
struct PermissionRuleListView: View {
  let title: String
  let iconColor: Color
  @Binding var rules: [String]
  @State private var newRule = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)

      if rules.isEmpty {
        Text("No rules")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .italic()
      }

      ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
        HStack(spacing: 4) {
          Image(systemName: "circle.fill")
            .font(.system(size: 5))
            .foregroundStyle(iconColor)

          Text(rule)
            .font(.caption)
            .fontDesign(.monospaced)
            .lineLimit(1)
            .truncationMode(.middle)

          Spacer()

          Button {
            rules.remove(at: index)
          } label: {
            Image(systemName: "minus.circle.fill")
              .font(.caption)
              .foregroundStyle(.red.opacity(0.7))
          }
          .buttonStyle(.plain)
        }
      }

      HStack(spacing: 4) {
        TextField("e.g. Bash(git *)", text: $newRule)
          .font(.caption)
          .fontDesign(.monospaced)
          .textFieldStyle(.roundedBorder)
          .onSubmit { addRule() }

        Button {
          addRule()
        } label: {
          Image(systemName: "plus.circle.fill")
            .font(.caption)
            .foregroundStyle(.green.opacity(newRule.isEmpty ? 0.3 : 0.7))
        }
        .buttonStyle(.plain)
        .disabled(newRule.isEmpty)
      }
    }
  }

  private func addRule() {
    let trimmed = newRule.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !rules.contains(trimmed) else { return }
    rules.append(trimmed)
    newRule = ""
  }
}

#Preview {
  @Previewable @State var rules = ["Bash(git *)", "Edit", "Read"]
  PermissionRuleListView(title: "Allowed Tools", iconColor: .green, rules: $rules)
    .padding()
    .frame(width: 300)
}

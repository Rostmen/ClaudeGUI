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

/// Shared permission editor used in both App Settings and Inspector Panel.
/// Takes a binding to `ClaudePermissionSettings` and provides:
/// - Permission mode picker
/// - Preset toggles for common configurations
/// - Allow/Deny/Ask rule lists with add/remove
/// - Raw JSON editor sheet
struct PermissionEditorView: View {
  @Binding var settings: ClaudePermissionSettings
  @State private var showRawEditor = false
  @State private var showPresets = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      modeSection
      presetsSection
      rulesSection
      rawEditorButton
    }
    .sheet(isPresented: $showRawEditor) {
      RawPermissionsEditorView(settings: $settings)
    }
  }

  // MARK: - Mode

  @ViewBuilder
  private var modeSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Permission Mode")
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)

      Picker("Mode", selection: $settings.permissionMode) {
        ForEach(ClaudePermissionMode.allCases) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .labelsHidden()

      Text(settings.permissionMode.description)
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
  }

  // MARK: - Presets

  @ViewBuilder
  private var presetsSection: some View {
    DisclosureGroup("Quick Presets", isExpanded: $showPresets) {
      VStack(alignment: .leading, spacing: 6) {
        PresetToggle(
          label: "Allow all file edits",
          rules: ["Edit", "Write"],
          activeRules: $settings.permissions.allow
        )
        PresetToggle(
          label: "Allow all bash commands",
          rules: ["Bash(*)"],
          activeRules: $settings.permissions.allow
        )
        PresetToggle(
          label: "Allow web access",
          rules: ["WebFetch", "WebSearch"],
          activeRules: $settings.permissions.allow
        )
        PresetToggle(
          label: "Allow all MCP tools",
          rules: ["mcp__*"],
          activeRules: $settings.permissions.allow
        )
      }
      .padding(.top, 4)
    }
    .font(.caption)
  }

  // MARK: - Rules

  @ViewBuilder
  private var rulesSection: some View {
    PermissionRuleListView(
      title: "Allowed Tools",
      iconColor: .green,
      rules: $settings.permissions.allow
    )

    PermissionRuleListView(
      title: "Denied Tools",
      iconColor: .red,
      rules: $settings.permissions.deny
    )

    PermissionRuleListView(
      title: "Ask Tools",
      iconColor: .yellow,
      rules: $settings.permissions.ask
    )
  }

  // MARK: - Raw Editor

  @ViewBuilder
  private var rawEditorButton: some View {
    Button {
      showRawEditor = true
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "curlybraces")
        Text("Edit Raw JSON")
      }
      .font(.caption)
    }
    .buttonStyle(.plain)
    .foregroundStyle(Color.accentColor)
  }
}

// MARK: - Preset Toggle

private struct PresetToggle: View {
  let label: String
  let rules: [String]
  @Binding var activeRules: [String]

  private var isActive: Bool {
    rules.allSatisfy { activeRules.contains($0) }
  }

  var body: some View {
    Toggle(label, isOn: Binding(
      get: { isActive },
      set: { enabled in
        if enabled {
          for rule in rules where !activeRules.contains(rule) {
            activeRules.append(rule)
          }
        } else {
          activeRules.removeAll { rules.contains($0) }
        }
      }
    ))
    .font(.caption)
  }
}

#Preview {
  @Previewable @State var settings = ClaudePermissionSettings(
    permissionMode: .default,
    permissions: ClaudePermissions(
      allow: ["Edit", "Bash(git *)"],
      deny: ["Bash(rm -rf *)"],
      ask: ["Write"]
    )
  )
  PermissionEditorView(settings: $settings)
    .padding()
    .frame(width: 300)
}

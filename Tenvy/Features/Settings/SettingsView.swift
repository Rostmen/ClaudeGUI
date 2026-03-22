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

struct SettingsView: View {
  @Bindable private var settings = AppSettings.shared
  @State private var hookService = HookInstallationService.shared
  @State private var isInstallingHooks = false
  @State private var isUninstallingHooks = false
  @State private var hookInstallResult: HookInstallResult?

  private enum HookInstallResult {
    case installSuccess(sessionsRestarted: Int)
    case uninstallSuccess(sessionsRestarted: Int)
    case failure(String)
  }

  var body: some View {
    Form {
#if DEBUG
      // Features section
      Section {
        Toggle("File Browser", isOn: $settings.fileTreeEnabled)
          .help("Show file browser tab in sidebar")

        Toggle("Git Changes", isOn: $settings.gitChangesEnabled)
          .help("Show git changes tab in sidebar")
      } header: {
        Text("Features")
      } footer: {
        Text("Disable features you don't need to improve performance")
          .font(.caption)
          .foregroundColor(.secondary)
      }
#endif
      // Hooks section
      Section {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Text("Claude Code Hooks")
              if hookService.hooksInstalled {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
                  .font(.caption)
              } else {
                Image(systemName: "xmark.circle.fill")
                  .foregroundColor(.orange)
                  .font(.caption)
              }
            }
            Text(hookService.hooksInstalled ? "Installed and active" : "Not installed")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          Spacer()

          HStack(spacing: 8) {
            Button(hookService.hooksInstalled ? "Reinstall" : "Install") {
              installHooks()
            }
            .disabled(isInstallingHooks || isUninstallingHooks)

            if hookService.hooksInstalled {
              Button("Uninstall") {
                uninstallHooks()
              }
              .disabled(isInstallingHooks || isUninstallingHooks)
            }
          }
        }

        if let result = hookInstallResult {
          switch result {
          case .installSuccess(let count):
            VStack(alignment: .leading, spacing: 2) {
              HStack {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
                Text("Hooks installed successfully")
                  .font(.caption)
              }
              if count > 0 {
                Text("\(count) active session\(count == 1 ? "" : "s") restarted")
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }
          case .uninstallSuccess(let count):
            VStack(alignment: .leading, spacing: 2) {
              HStack {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
                Text("Hooks uninstalled successfully")
                  .font(.caption)
              }
              if count > 0 {
                Text("\(count) active session\(count == 1 ? "" : "s") restarted")
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }
          case .failure(let error):
            HStack {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
              Text(error)
                .font(.caption)
                .foregroundColor(.red)
            }
          }
        }

        if settings.hookPromptDismissed {
          Button("Re-enable installation prompts") {
            settings.hookPromptDismissed = false
          }
          .font(.caption)
        }
      } header: {
        Text("Session State Tracking")
      } footer: {
        Text("Hooks enable real-time status like \"Reading file...\" and \"Waiting\" in the sidebar")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 350, height: 380)
    .onAppear {
      hookService.checkInstallationStatus()
    }
  }

  private func installHooks() {
    isInstallingHooks = true
    hookInstallResult = nil

    Task {
      let result = await hookService.installHooks()

      await MainActor.run {
        isInstallingHooks = false
        switch result {
        case .success:
          // Restart active sessions to apply hooks
          let sessionCount = TerminalRegistry.shared.activeSessionCount
          TerminalRegistry.shared.restartAllSessions()
          hookInstallResult = .installSuccess(sessionsRestarted: sessionCount)
        case .failure(let error):
          hookInstallResult = .failure(error.localizedDescription)
        }
      }
    }
  }

  private func uninstallHooks() {
    isUninstallingHooks = true
    hookInstallResult = nil

    Task {
      let result = await hookService.uninstallHooks()

      await MainActor.run {
        isUninstallingHooks = false
        switch result {
        case .success:
          // Clear all cached hook states
          HookEventService.shared.clearAllStates()
          AppState.shared.runtimeState.resetAllHookStates()

          // Restart active sessions to apply hook removal
          let sessionCount = TerminalRegistry.shared.activeSessionCount
          TerminalRegistry.shared.restartAllSessions()
          hookInstallResult = .uninstallSuccess(sessionsRestarted: sessionCount)
        case .failure(let error):
          hookInstallResult = .failure(error.localizedDescription)
        }
      }
    }
  }
}

#Preview {
  SettingsView()
}

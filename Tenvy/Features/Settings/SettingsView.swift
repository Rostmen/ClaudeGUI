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
import Foundation
import CodeEditor

struct SettingsView: View {
  @Environment(AppModel.self) private var appModel
  @Bindable private var settings = AppSettings.shared
  @State private var isInstallingHooks = false
  @State private var isUninstallingHooks = false
  @State private var hookInstallResult: HookInstallResult?
  @State private var newEnvKey = ""
  @State private var newEnvValue = ""

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

      // Appearance section
      Section {
        Picker("Appearance", selection: $settings.appearanceMode) {
          ForEach(AppearanceMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(MenuPickerStyle())
      } header: {
        Text("Appearance")
      } footer: {
        Text("System follows your macOS appearance setting automatically.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      // Hooks section
      Section {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Text("Claude Code Hooks")
              if appModel.hookSetup.hooksInstalled {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
                  .font(.caption)
              } else {
                Image(systemName: "xmark.circle.fill")
                  .foregroundColor(.orange)
                  .font(.caption)
              }
            }
            Text(appModel.hookSetup.hooksInstalled ? "Installed and active" : "Not installed")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          Spacer()

          HStack(spacing: 8) {
            Button(appModel.hookSetup.hooksInstalled ? "Reinstall" : "Install") {
              installHooks()
            }
            .disabled(isInstallingHooks || isUninstallingHooks)

            if appModel.hookSetup.hooksInstalled {
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

      // Shell Init Script section
      Section {
        CodeEditor(source: $settings.shellInitScript, language: .bash, theme: .ocean)
          .frame(height: 120)
          .clipShape(RoundedRectangle(cornerRadius: 6))

        HStack {
          Spacer()
          Button("Reset to Default") {
            settings.shellInitScript = AppSettings.defaultShellInitScript
          }
          .font(.caption)
          .disabled(settings.shellInitScript == AppSettings.defaultShellInitScript)
        }
      } header: {
        Text("Shell Start-up Script")
      } footer: {
        Text("Bash script executed before launching each terminal session. Runs inside the login shell before `exec`.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      // Environment Variables section
      Section {
        let sorted = settings.customEnvironmentVariables.sorted { $0.key < $1.key }
        ForEach(sorted, id: \.key) { key, value in
          HStack(spacing: 4) {
            Text(key)
              .font(.system(.caption, design: .monospaced))
            Text("=")
              .foregroundStyle(.tertiary)
            Text(value)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.tail)
            Spacer()
            Button {
              settings.customEnvironmentVariables.removeValue(forKey: key)
            } label: {
              Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
          }
        }

        HStack(spacing: 6) {
          TextField("KEY", text: $newEnvKey)
            .font(.system(.caption, design: .monospaced))
            .frame(minWidth: 80)
          Text("=")
            .foregroundStyle(.secondary)
          TextField("value", text: $newEnvValue)
            .font(.system(.caption, design: .monospaced))
          Button {
            let key = newEnvKey.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return }
            settings.customEnvironmentVariables[key] = newEnvValue
            newEnvKey = ""
            newEnvValue = ""
          } label: {
            Image(systemName: "plus.circle.fill")
              .foregroundStyle(.green)
          }
          .buttonStyle(.plain)
          .disabled(newEnvKey.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      } header: {
        Text("Environment Variables")
      } footer: {
        Text("Injected into every terminal session, applied after ~/.zshrc is sourced.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 600)
    .onAppear {
      appModel.hookSetup.checkInstallationStatus()
    }
  }

  private func installHooks() {
    isInstallingHooks = true
    hookInstallResult = nil

    Task {
      let result = await appModel.hookSetup.installHooks()

      await MainActor.run {
        isInstallingHooks = false
        switch result {
        case .success:
          // Restart active sessions to apply hooks
          let sessionCount = appModel.terminalInput.activeSessionCount
          appModel.terminalInput.restartAllSessions()
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
      let result = await appModel.hookSetup.uninstallHooks()

      await MainActor.run {
        isUninstallingHooks = false
        switch result {
        case .success:
          // Clear all cached hook states
          appModel.hookMonitor.clearAllStates()
          appModel.runtimeRegistry.resetAllHookStates()

          // Restart active sessions to apply hook removal
          let sessionCount = appModel.terminalInput.activeSessionCount
          appModel.terminalInput.restartAllSessions()
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
    .environment(AppModel())
}

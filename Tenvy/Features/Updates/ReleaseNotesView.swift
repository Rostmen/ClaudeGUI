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

/// Displays release notes for a given app version in a scrollable view.
/// Hosted inside a standalone NSWindow shown on first launch of a new version.
struct ReleaseNotesView: View {
  let version: String
  let releaseNotes: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView {
        Text(releaseNotes)
          .font(.body)
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(20)
          .textSelection(.enabled)
      }
    }
    .frame(width: 560, height: 480)
  }
}

#Preview("Release Notes") {
  ReleaseNotesView(
    version: "1.2.0",
    releaseNotes: """
    ## Tenvy v1.2.0

    ### What's New
    - Added update checker with bottom-right prompt
    - Release notes window shown on first launch of a new version
    - Improved session state monitoring

    ### Bug Fixes
    - Fixed window restoration on launch
    - Fixed process cleanup on app quit
    """
  )
}

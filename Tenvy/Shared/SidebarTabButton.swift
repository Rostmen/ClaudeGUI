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

struct SidebarTabButton: View {
  let tab: SidebarTab
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: tab.icon)
        .font(.system(size: 15, weight: .regular))
        .frame(width: 38, height: 28)
        .foregroundColor(isSelected ? .white : Color(nsColor: NSColor(white: 0.55, alpha: 1)))
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
    .buttonStyle(.plain)
    .help(tab.label)
  }
}

#Preview("Selected") {
  SidebarTabButton(tab: .sessions, isSelected: true, action: {})
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("Unselected") {
  SidebarTabButton(tab: .files, isSelected: false, action: {})
    .padding()
    .background(Color.black.opacity(0.8))
}

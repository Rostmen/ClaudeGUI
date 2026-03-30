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

/// Service for grouping and filtering sessions by working directory or date
struct SessionGroupingService {
  /// A group of sessions sharing a common label (folder path or date heading)
  struct SessionGroup: Identifiable {
    let folder: String
    let sessions: [ClaudeSession]

    var id: String { folder }
  }

  /// Group sessions by their working directory, sorted alphabetically by folder name
  /// Sessions within each group are sorted by last modified (newest first)
  static func groupByWorkingDirectory(_ sessions: [ClaudeSession]) -> [SessionGroup] {
    let grouped = Dictionary(grouping: sessions) { $0.workingDirectory }

    return grouped
      .map { SessionGroup(folder: $0.key, sessions: $0.value.sorted { $0.lastModified > $1.lastModified }) }
      .sorted { folderName($0.folder) < folderName($1.folder) }
  }

  /// Group sessions by day (based on `lastModified`), most recent day first.
  /// Sessions within each day are sorted newest first.
  static func groupByDate(_ sessions: [ClaudeSession]) -> [SessionGroup] {
    let calendar = Calendar.current
    let now = Date()
    let grouped = Dictionary(grouping: sessions) { session in
      calendar.startOfDay(for: session.lastModified)
    }

    return grouped
      .map { (day, sessions) in
        SessionGroup(
          folder: dayLabel(for: day, now: now, calendar: calendar),
          sessions: sessions.sorted { $0.lastModified > $1.lastModified }
        )
      }
      .sorted { $0.sessions.first!.lastModified > $1.sessions.first!.lastModified }
  }

  /// Human-readable label for a day: "Today", "Yesterday", or a formatted date.
  private static func dayLabel(for day: Date, now: Date, calendar: Calendar) -> String {
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    let daysAgo = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day ?? 0
    if daysAgo < 7 {
      let formatter = DateFormatter()
      formatter.dateFormat = "EEEE" // e.g. "Thursday"
      return formatter.string(from: day)
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy"
    return formatter.string(from: day)
  }

  /// Filter sessions by search text (matches title or working directory)
  static func filter(_ sessions: [ClaudeSession], by searchText: String) -> [ClaudeSession] {
    guard !searchText.isEmpty else { return sessions }

    return sessions.filter { session in
      session.title.localizedCaseInsensitiveContains(searchText) ||
      session.workingDirectory.localizedCaseInsensitiveContains(searchText)
    }
  }

  /// Group and filter sessions in one call
  static func groupAndFilter(_ sessions: [ClaudeSession], searchText: String) -> [SessionGroup] {
    let filtered = filter(sessions, by: searchText)
    return groupByWorkingDirectory(filtered)
  }

  /// Extract just the folder name from a path
  static func folderName(_ path: String) -> String {
    (path as NSString).lastPathComponent
  }

  /// Format folder path for display (replaces home directory with ~)
  static func displayPath(_ path: String) -> String {
    path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
  }
}

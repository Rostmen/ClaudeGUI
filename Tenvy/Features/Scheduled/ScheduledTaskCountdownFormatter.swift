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

/// Formats the relative-only countdown shown on scheduled-task rows.
///
/// Decision (clarification round 7): relative duration only — no wall-clock fallbacks.
/// Output examples: `"in 12s"`, `"in 3m 45s"`, `"in 2h 14m"`, `"in 3 days"`, `"due now"`.
enum ScheduledTaskCountdownFormatter {

  static func relative(from now: Date, to next: Date) -> String {
    let interval = next.timeIntervalSince(now)
    if interval <= 0 { return "due now" }

    let total = Int(interval.rounded())
    if total < 60 {
      return "in \(total)s"
    }
    if total < 3_600 {
      let m = total / 60
      let s = total % 60
      if s == 0 { return "in \(m)m" }
      return "in \(m)m \(s)s"
    }
    if total < 86_400 {
      let h = total / 3_600
      let m = (total % 3_600) / 60
      if m == 0 { return "in \(h)h" }
      return "in \(h)h \(m)m"
    }
    // Days: round to whole days from `now` to `next` in the user's calendar so that
    // "tomorrow at the same time" reads as 1 day (not 23h or 25h depending on DST).
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: next)).day ?? 0
    let resolved = max(days, 1)
    if resolved == 1 { return "in 1 day" }
    return "in \(resolved) days"
  }

  /// Refresh interval to use for a `TimelineView`'s `.periodic(...)` schedule so that the
  /// displayed countdown stays accurate without burning CPU on million ticks per second.
  static func refreshInterval(remaining: TimeInterval) -> TimeInterval {
    switch remaining {
    case ..<60: return 1
    case ..<3_600: return 15
    case ..<86_400: return 60
    default: return 600
    }
  }
}

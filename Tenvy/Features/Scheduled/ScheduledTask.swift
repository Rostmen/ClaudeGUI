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

// MARK: - Frequency unit

enum ScheduledTaskFrequencyUnit: String, Codable, CaseIterable, Identifiable {
  case minute
  case hour
  case day
  case week

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .minute: "Minutes"
    case .hour: "Hours"
    case .day: "Days"
    case .week: "Weeks"
    }
  }

  var requiresTimeOfDay: Bool { self == .day || self == .week }
  var requiresWeekdays: Bool { self == .week }
}

// MARK: - Time of day

struct ScheduledTaskTimeOfDay: Codable, Equatable, Hashable {
  let hour: Int
  let minute: Int

  var isValid: Bool { (0...23).contains(hour) && (0...59).contains(minute) }

  var displayString: String { String(format: "%02d:%02d", hour, minute) }
}

// MARK: - Weekday

/// ISO weekday (1=Sunday … 7=Saturday — matches `Calendar.weekday`).
enum ScheduledTaskWeekday: Int, Codable, CaseIterable, Identifiable, Comparable {
  case sunday = 1
  case monday = 2
  case tuesday = 3
  case wednesday = 4
  case thursday = 5
  case friday = 6
  case saturday = 7

  var id: Int { rawValue }

  static func < (lhs: ScheduledTaskWeekday, rhs: ScheduledTaskWeekday) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  var shortName: String {
    let symbols = Calendar.current.shortWeekdaySymbols
    return symbols[rawValue - 1]
  }

  var narrowName: String {
    let symbols = Calendar.current.veryShortWeekdaySymbols
    return symbols[rawValue - 1]
  }

  /// Comma-joined encoding for storage (e.g., "1,2,5").
  static func encode(_ days: Set<ScheduledTaskWeekday>) -> String {
    days.map { String($0.rawValue) }.sorted().joined(separator: ",")
  }

  static func decode(_ string: String?) -> Set<ScheduledTaskWeekday> {
    guard let string, !string.isEmpty else { return [] }
    return Set(string.split(separator: ",").compactMap {
      Int($0).flatMap(ScheduledTaskWeekday.init(rawValue:))
    })
  }

  /// Locale-aware iteration order, starting at the calendar's first weekday.
  static func orderedForCurrentLocale() -> [ScheduledTaskWeekday] {
    let first = Calendar.current.firstWeekday
    return (0..<7).map {
      let raw = ((first - 1 + $0) % 7) + 1
      return ScheduledTaskWeekday(rawValue: raw)!
    }
  }
}

// MARK: - Prompt kind

enum ScheduledTaskPromptKind: String, Codable, CaseIterable, Identifiable {
  case text
  case file

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .text: "Text"
    case .file: "File"
    }
  }
}

// MARK: - Run status

enum ScheduledTaskRunStatus: String, Codable {
  case running
  case completed
  case skipped
  case failed
}

// MARK: - Frequency

struct ScheduledTaskFrequency: Codable, Equatable {
  let unit: ScheduledTaskFrequencyUnit
  let value: Int
  let timeOfDay: ScheduledTaskTimeOfDay?
  let weekdays: Set<ScheduledTaskWeekday>?

  /// Returns a validation error message, or nil if the frequency is valid.
  func validationError() -> String? {
    guard value >= 1, value <= 999 else {
      return "Frequency value must be between 1 and 999."
    }
    if unit.requiresTimeOfDay {
      guard let time = timeOfDay, time.isValid else {
        return "Time of day is required for \(unit.displayName)."
      }
    } else if timeOfDay != nil {
      return "Time of day is not used for \(unit.displayName)."
    }
    if unit.requiresWeekdays {
      guard let days = weekdays, !days.isEmpty else {
        return "Select at least one weekday."
      }
    } else if let days = weekdays, !days.isEmpty {
      return "Weekdays are not used for \(unit.displayName)."
    }
    return nil
  }

  /// Human-readable summary (e.g., "Every 2 weeks on Mon, Wed at 09:00").
  var displayString: String {
    let n = value
    switch unit {
    case .minute:
      return n == 1 ? "Every minute" : "Every \(n) minutes"
    case .hour:
      return n == 1 ? "Every hour" : "Every \(n) hours"
    case .day:
      let suffix = timeOfDay.map { " at \($0.displayString)" } ?? ""
      return n == 1 ? "Every day\(suffix)" : "Every \(n) days\(suffix)"
    case .week:
      let days = (weekdays ?? [])
        .sorted()
        .map { $0.shortName }
        .joined(separator: ", ")
      let suffix = timeOfDay.map { " at \($0.displayString)" } ?? ""
      let dayPart = days.isEmpty ? "" : " on \(days)"
      return n == 1 ? "Every week\(dayPart)\(suffix)" : "Every \(n) weeks\(dayPart)\(suffix)"
    }
  }

  // MARK: - Next-run computation

  /// Computes the next valid run time strictly after `anchor`.
  ///
  /// `createdAt` is used as the phase reference for "every N days/weeks" — the
  /// modulo-N relationship is anchored at the creation day/week. `anchor` is
  /// usually `max(lastRunAt, now)` or the re-enable time.
  func nextRunAt(
    createdAt: Date,
    from anchor: Date,
    calendar: Calendar = .current
  ) -> Date {
    switch unit {
    case .minute:
      return anchor.addingTimeInterval(TimeInterval(value * 60))
    case .hour:
      return anchor.addingTimeInterval(TimeInterval(value * 3600))
    case .day:
      return nextDay(createdAt: createdAt, from: anchor, calendar: calendar)
    case .week:
      return nextWeek(createdAt: createdAt, from: anchor, calendar: calendar)
    }
  }

  private func nextDay(createdAt: Date, from anchor: Date, calendar: Calendar) -> Date {
    guard let time = timeOfDay else { return anchor }
    let createdStart = calendar.startOfDay(for: createdAt)
    var candidate = setTimeOfDay(time, onDayOf: anchor, calendar: calendar)
    // Safety cap: ~4 years of days for value=999.
    for _ in 0..<(value * 366 + 366) {
      if candidate > anchor {
        let candidateStart = calendar.startOfDay(for: candidate)
        let dayDiff = calendar.dateComponents([.day], from: createdStart, to: candidateStart).day ?? 0
        if value <= 1 || (dayDiff % value) == 0 {
          return candidate
        }
      }
      candidate = advanceOneDay(candidate, applying: time, calendar: calendar)
    }
    // Fallback: simple linear step.
    return anchor.addingTimeInterval(TimeInterval(value * 86400))
  }

  private func nextWeek(createdAt: Date, from anchor: Date, calendar: Calendar) -> Date {
    guard let time = timeOfDay,
          let days = weekdays, !days.isEmpty else { return anchor }
    let weekdayIds = Set(days.map(\.rawValue))
    let createdWeekStart = startOfWeek(for: createdAt, calendar: calendar)
    var candidate = setTimeOfDay(time, onDayOf: anchor, calendar: calendar)
    // Safety cap: ~4 years of days for value=999.
    for _ in 0..<(value * 7 * 53 + 7) {
      let weekday = calendar.component(.weekday, from: candidate)
      if weekdayIds.contains(weekday) && candidate > anchor {
        let weekStart = startOfWeek(for: candidate, calendar: calendar)
        let weekDiff = calendar.dateComponents([.weekOfYear], from: createdWeekStart, to: weekStart).weekOfYear ?? 0
        if value <= 1 || (weekDiff % value) == 0 {
          return candidate
        }
      }
      candidate = advanceOneDay(candidate, applying: time, calendar: calendar)
    }
    return anchor.addingTimeInterval(TimeInterval(value * 7 * 86400))
  }

  // MARK: helpers

  private func setTimeOfDay(_ time: ScheduledTaskTimeOfDay, onDayOf date: Date, calendar: Calendar) -> Date {
    var comps = calendar.dateComponents([.year, .month, .day], from: date)
    comps.hour = time.hour
    comps.minute = time.minute
    comps.second = 0
    return calendar.date(from: comps) ?? date
  }

  private func advanceOneDay(_ date: Date, applying time: ScheduledTaskTimeOfDay, calendar: Calendar) -> Date {
    let next = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
    return setTimeOfDay(time, onDayOf: next, calendar: calendar)
  }

  private func startOfWeek(for date: Date, calendar: Calendar) -> Date {
    let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return calendar.date(from: comps) ?? date
  }
}

// MARK: - Slugify

enum ScheduledTaskNaming {
  /// Lowercase alphanumeric+dash slug, max 32 chars; falls back to `task-<8-char-id>` if empty.
  static func slug(name: String, fallbackId: String) -> String {
    let lower = name.lowercased().folding(options: .diacriticInsensitive, locale: .current)
    var out = ""
    var lastWasDash = true
    for scalar in lower.unicodeScalars {
      let c = Character(scalar)
      if c.isLetter || c.isNumber {
        out.append(c)
        lastWasDash = false
      } else if !lastWasDash {
        out.append("-")
        lastWasDash = true
      }
    }
    while out.hasSuffix("-") { out.removeLast() }
    if out.count > 32 {
      out = String(out.prefix(32))
      while out.hasSuffix("-") { out.removeLast() }
    }
    if out.isEmpty {
      let head = fallbackId.replacingOccurrences(of: "-", with: "").prefix(8)
      return "task-\(head)"
    }
    return out
  }

  /// `yyyyMMdd-HHmmss` in UTC for branch + worktree names.
  static func timestamp(_ date: Date = Date()) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyyMMdd-HHmmss"
    fmt.timeZone = TimeZone(identifier: "UTC")
    fmt.locale = Locale(identifier: "en_US_POSIX")
    return fmt.string(from: date)
  }

  /// Local-time human-readable suffix for session titles (e.g., "2026-05-15 14:30").
  static func titleTimestamp(_ date: Date = Date()) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm"
    fmt.locale = Locale(identifier: "en_US_POSIX")
    return fmt.string(from: date)
  }

  /// Branch name candidate: `tenvy/scheduled/<slug>/<ts>` plus optional collision suffix.
  static func branchName(slug: String, timestamp: String, collisionSuffix: Int? = nil) -> String {
    let suffix = collisionSuffix.map { "-\($0)" } ?? ""
    return "tenvy/scheduled/\(slug)/\(timestamp)\(suffix)"
  }

  /// Worktree directory name (flat, no slashes): `<slug>-<ts>` plus optional collision suffix.
  static func worktreeDirName(slug: String, timestamp: String, collisionSuffix: Int? = nil) -> String {
    let suffix = collisionSuffix.map { "-\($0)" } ?? ""
    return "\(slug)-\(timestamp)\(suffix)"
  }
}

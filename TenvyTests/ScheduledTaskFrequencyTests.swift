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
import Testing
@testable import Tenvy

/// Tests for `ScheduledTaskFrequency.nextRunAt(...)` and `validationError()`.
struct ScheduledTaskFrequencyTests {

  // MARK: - Helpers

  private static let gmt: TimeZone = TimeZone(identifier: "UTC")!

  private static func gmtCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = gmt
    cal.firstWeekday = 1 // Sunday — stable for tests
    return cal
  }

  /// Build a UTC date from components.
  private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    let cal = gmtCalendar()
    return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
  }

  // MARK: - Minute / hour intervals

  @Test
  func minuteInterval_addsExactlyNMinutes() {
    let f = ScheduledTaskFrequency(unit: .minute, value: 5, timeOfDay: nil, weekdays: nil)
    let anchor = Self.date(2026, 5, 15, 10, 00)
    let next = f.nextRunAt(createdAt: anchor, from: anchor, calendar: Self.gmtCalendar())
    #expect(next == Self.date(2026, 5, 15, 10, 05))
  }

  @Test
  func hourInterval_addsExactlyNHours() {
    let f = ScheduledTaskFrequency(unit: .hour, value: 3, timeOfDay: nil, weekdays: nil)
    let anchor = Self.date(2026, 5, 15, 10, 30)
    let next = f.nextRunAt(createdAt: anchor, from: anchor, calendar: Self.gmtCalendar())
    #expect(next == Self.date(2026, 5, 15, 13, 30))
  }

  // MARK: - Day frequency

  @Test
  func day_N1_timeInFuture_returnsSameDayAtTime() {
    let f = ScheduledTaskFrequency(
      unit: .day,
      value: 1,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 14, minute: 30),
      weekdays: nil
    )
    let anchor = Self.date(2026, 5, 15, 9, 0)
    let next = f.nextRunAt(createdAt: anchor, from: anchor, calendar: Self.gmtCalendar())
    #expect(next == Self.date(2026, 5, 15, 14, 30))
  }

  @Test
  func day_N1_timeInPast_returnsTomorrow() {
    let f = ScheduledTaskFrequency(
      unit: .day,
      value: 1,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 9, minute: 0),
      weekdays: nil
    )
    let anchor = Self.date(2026, 5, 15, 10, 0)
    let next = f.nextRunAt(createdAt: anchor, from: anchor, calendar: Self.gmtCalendar())
    #expect(next == Self.date(2026, 5, 16, 9, 0))
  }

  @Test
  func day_N2_skipsOneDay() {
    let f = ScheduledTaskFrequency(
      unit: .day,
      value: 2,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 9, minute: 0),
      weekdays: nil
    )
    let createdAt = Self.date(2026, 5, 15, 9, 0)  // Friday
    let anchor = Self.date(2026, 5, 15, 10, 0)    // Friday 10am (after creation)
    let next = f.nextRunAt(createdAt: createdAt, from: anchor, calendar: Self.gmtCalendar())
    // From Fri 9am base, valid days are Fri, Sun, Tue... So next > Fri 10am is Sun 9am.
    #expect(next == Self.date(2026, 5, 17, 9, 0))
  }

  @Test
  func day_N3_returnsThirdDay() {
    let f = ScheduledTaskFrequency(
      unit: .day,
      value: 3,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 9, minute: 0),
      weekdays: nil
    )
    let createdAt = Self.date(2026, 5, 15, 9, 0)
    let anchor = Self.date(2026, 5, 15, 10, 0)
    let next = f.nextRunAt(createdAt: createdAt, from: anchor, calendar: Self.gmtCalendar())
    // Valid days: 5/15, 5/18, 5/21... Next > 5/15 10am is 5/18 9am.
    #expect(next == Self.date(2026, 5, 18, 9, 0))
  }

  // MARK: - Week frequency

  @Test
  func week_N1_singleWeekday_returnsNextOccurrence() {
    // 2026-05-15 is Friday. Weekday=6 in Gregorian (1=Sun…7=Sat).
    let f = ScheduledTaskFrequency(
      unit: .week,
      value: 1,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 9, minute: 0),
      weekdays: [.wednesday]
    )
    let anchor = Self.date(2026, 5, 15, 9, 0) // Friday
    let next = f.nextRunAt(createdAt: anchor, from: anchor, calendar: Self.gmtCalendar())
    // Next Wednesday is 2026-05-20.
    #expect(next == Self.date(2026, 5, 20, 9, 0))
  }

  @Test
  func week_N1_multipleWeekdays_returnsEarliestNext() {
    let f = ScheduledTaskFrequency(
      unit: .week,
      value: 1,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 9, minute: 0),
      weekdays: [.monday, .wednesday, .friday]
    )
    let anchor = Self.date(2026, 5, 15, 10, 0) // Friday 10am
    let next = f.nextRunAt(createdAt: anchor, from: anchor, calendar: Self.gmtCalendar())
    // From Fri 10am, next is Mon 5/18 9am.
    #expect(next == Self.date(2026, 5, 18, 9, 0))
  }

  @Test
  func week_N1_weekdayIsTodayInFuture_returnsToday() {
    let f = ScheduledTaskFrequency(
      unit: .week,
      value: 1,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 14, minute: 0),
      weekdays: [.friday]
    )
    let anchor = Self.date(2026, 5, 15, 9, 0) // Friday 9am
    let next = f.nextRunAt(createdAt: anchor, from: anchor, calendar: Self.gmtCalendar())
    // Same Friday, later in day.
    #expect(next == Self.date(2026, 5, 15, 14, 0))
  }

  @Test
  func week_N2_skipsOneWeek() {
    let f = ScheduledTaskFrequency(
      unit: .week,
      value: 2,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 9, minute: 0),
      weekdays: [.monday]
    )
    let createdAt = Self.date(2026, 5, 11, 9, 0) // Monday (week reference)
    let anchor = Self.date(2026, 5, 11, 10, 0)   // Mon 10am, same week
    let next = f.nextRunAt(createdAt: createdAt, from: anchor, calendar: Self.gmtCalendar())
    // Mon 5/11 = week 0 (valid), Mon 5/18 = week 1 (skip), Mon 5/25 = week 2 (valid).
    #expect(next == Self.date(2026, 5, 25, 9, 0))
  }

  // MARK: - DST

  @Test
  func day_timeOfDayHandlesSpringForwardInLocalTimeZone() throws {
    // Use America/New_York: DST starts on 2026-03-08 — clocks jump from 2:00 to 3:00 AM local.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    cal.firstWeekday = 1

    let f = ScheduledTaskFrequency(
      unit: .day,
      value: 1,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 9, minute: 0),
      weekdays: nil
    )
    // Anchor is March 7 8am NYC — next slot should be March 7 9am NYC.
    let anchor = cal.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 8, minute: 0))!
    let next = f.nextRunAt(createdAt: anchor, from: anchor, calendar: cal)
    let expected = cal.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9, minute: 0))!
    #expect(next == expected)

    // Anchor is March 7 10am — should jump to March 8 9am NYC even though DST occurs that morning.
    let anchor2 = cal.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 10, minute: 0))!
    let next2 = f.nextRunAt(createdAt: anchor2, from: anchor2, calendar: cal)
    let expected2 = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9, minute: 0))!
    #expect(next2 == expected2)
  }

  // MARK: - Validation

  @Test
  func validation_minute_acceptsNoTimeOrWeekday() {
    let f = ScheduledTaskFrequency(unit: .minute, value: 5, timeOfDay: nil, weekdays: nil)
    #expect(f.validationError() == nil)
  }

  @Test
  func validation_day_requiresTimeOfDay() {
    let f = ScheduledTaskFrequency(unit: .day, value: 1, timeOfDay: nil, weekdays: nil)
    #expect(f.validationError() != nil)
  }

  @Test
  func validation_week_requiresWeekdays() {
    let f = ScheduledTaskFrequency(
      unit: .week,
      value: 1,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 9, minute: 0),
      weekdays: []
    )
    #expect(f.validationError() != nil)
  }

  @Test
  func validation_week_requiresTimeOfDay() {
    let f = ScheduledTaskFrequency(
      unit: .week,
      value: 1,
      timeOfDay: nil,
      weekdays: [.monday]
    )
    #expect(f.validationError() != nil)
  }

  @Test
  func validation_rejectsZeroValue() {
    let f = ScheduledTaskFrequency(unit: .minute, value: 0, timeOfDay: nil, weekdays: nil)
    #expect(f.validationError() != nil)
  }

  @Test
  func validation_rejectsExcessiveValue() {
    let f = ScheduledTaskFrequency(unit: .minute, value: 1000, timeOfDay: nil, weekdays: nil)
    #expect(f.validationError() != nil)
  }

  @Test
  func validation_minute_rejectsTimeOfDay() {
    let f = ScheduledTaskFrequency(
      unit: .minute,
      value: 5,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 9, minute: 0),
      weekdays: nil
    )
    #expect(f.validationError() != nil)
  }

  @Test
  func validation_day_rejectsWeekdays() {
    let f = ScheduledTaskFrequency(
      unit: .day,
      value: 1,
      timeOfDay: ScheduledTaskTimeOfDay(hour: 9, minute: 0),
      weekdays: [.monday]
    )
    #expect(f.validationError() != nil)
  }

  // MARK: - Slug + naming

  @Test
  func slug_lowercasesAndStripsSpecials() {
    let s = ScheduledTaskNaming.slug(name: "My Daily Task!", fallbackId: "x")
    #expect(s == "my-daily-task")
  }

  @Test
  func slug_handlesUnicodeViaFolding() {
    let s = ScheduledTaskNaming.slug(name: "café review", fallbackId: "x")
    #expect(s == "cafe-review")
  }

  @Test
  func slug_truncatesTo32Chars() {
    let s = ScheduledTaskNaming.slug(
      name: String(repeating: "a", count: 100),
      fallbackId: "x"
    )
    #expect(s.count <= 32)
  }

  @Test
  func slug_fallbackOnEmpty() {
    let id = "1234ABCD-5678-9abc-def0-123456789012"
    let s = ScheduledTaskNaming.slug(name: "!!!", fallbackId: id)
    #expect(s.hasPrefix("task-"))
    #expect(s.count == "task-".count + 8)
  }

  @Test
  func branchName_followsTenvyScheduledFormat() {
    let b = ScheduledTaskNaming.branchName(slug: "demo", timestamp: "20260515-093000")
    #expect(b == "tenvy/scheduled/demo/20260515-093000")
  }

  @Test
  func branchName_appendsCollisionSuffix() {
    let b = ScheduledTaskNaming.branchName(slug: "demo", timestamp: "20260515-093000", collisionSuffix: 3)
    #expect(b == "tenvy/scheduled/demo/20260515-093000-3")
  }

  @Test
  func worktreeDirName_flatNoSlashes() {
    let w = ScheduledTaskNaming.worktreeDirName(slug: "demo", timestamp: "20260515-093000")
    #expect(w == "demo-20260515-093000")
  }
}

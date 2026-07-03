import Testing
import Foundation
@testable import TableTogetherLib

@Suite("MealType Tests")
struct MealTypeTests {

    @Test("All meal types have unique raw values")
    func uniqueRawValues() {
        let raws = MealType.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
    }

    @Test("Sort order is monotonic")
    func sortOrderMonotonic() {
        let sorted = MealType.allCases.sorted { $0.sortOrder < $1.sortOrder }
        #expect(sorted == [.breakfast, .lunch, .dinner, .snack])
    }

    @Test("Default planned meals includes all meal types")
    func defaultPlannedMealsIncludesAll() {
        #expect(Set(MealType.defaultPlannedMeals) == Set(MealType.allCases))
    }

    @Test("Display name is non-empty for all cases")
    func displayNamesArePresent() {
        for type in MealType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    @Test("Icon name is non-empty for all cases")
    func iconNamesArePresent() {
        for type in MealType.allCases {
            #expect(!type.iconName.isEmpty)
            #expect(type.icon == type.iconName)
        }
    }
}

@Suite("DayOfWeek Tests")
struct DayOfWeekTests {

    @Test("Monday is the first day with raw value 1")
    func mondayIsFirst() {
        #expect(DayOfWeek.monday.rawValue == 1)
    }

    @Test("Weekend correctly identifies Saturday and Sunday")
    func weekendIdentification() {
        #expect(DayOfWeek.saturday.isWeekend)
        #expect(DayOfWeek.sunday.isWeekend)
        #expect(!DayOfWeek.monday.isWeekend)
        #expect(!DayOfWeek.friday.isWeekend)
    }

    @Test("All days have unique short names")
    func uniqueShortNames() {
        let names = DayOfWeek.allCases.map(\.shortName)
        #expect(Set(names).count == names.count)
    }

    @Test("Display name matches full name")
    func displayNameMatchesFullName() {
        for day in DayOfWeek.allCases {
            #expect(day.displayName == day.fullName)
        }
    }

    @Test("day(for:) maps Calendar weekdays to Monday-first days")
    func dayForDateMapsWeekdays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        // 2026-07-03 is a Friday; 2026-07-05 is a Sunday; 2026-06-29 a Monday.
        let friday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3))!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 5))!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 29))!

        #expect(DayOfWeek.day(for: friday, calendar: calendar) == .friday)
        #expect(DayOfWeek.day(for: sunday, calendar: calendar) == .sunday)
        #expect(DayOfWeek.day(for: monday, calendar: calendar) == .monday)
    }

    @Test("remaining(from:) runs from the given day through Sunday")
    func remainingDaysThroughSunday() {
        #expect(DayOfWeek.remaining(from: .friday) == [.friday, .saturday, .sunday])
        #expect(DayOfWeek.remaining(from: .monday) == DayOfWeek.allCases)
        #expect(DayOfWeek.remaining(from: .sunday) == [.sunday])
    }
}

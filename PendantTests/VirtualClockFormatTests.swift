import Foundation
import Testing
@testable import Pendant

struct VirtualClockFormatTests {
    private var date: Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 22; parts.hour = 19; parts.minute = 5; parts.second = 9
        return Calendar(identifier: .gregorian).date(from: parts)!
    }

    private let posix = Locale(identifier: "en_US_POSIX")

    @Test func twentyFourHour() {
        #expect(VirtualClockFormat.string(for: date, use24Hour: true, seconds: false, showsDate: false, locale: posix) == "19:05")
        #expect(VirtualClockFormat.string(for: date, use24Hour: true, seconds: true, showsDate: false, locale: posix) == "19:05:09")
    }

    @Test func twelveHour() {
        #expect(VirtualClockFormat.string(for: date, use24Hour: false, seconds: false, showsDate: false, locale: posix) == "7:05 PM")
    }

    private let taiwan = Locale(identifier: "zh_TW")

    @Test func dateIsChineseAndComesBeforeTheTime() {
        #expect(VirtualClockFormat.string(for: date, use24Hour: true, seconds: false, showsDate: true, locale: taiwan) == "10月22日 週四 19:05")
    }

    @Test func dateIsEnglishInEnglishMode() {
        #expect(VirtualClockFormat.date(date, format: .monthDay, locale: Locale(identifier: "en_US")) == "Oct 22, Thu")
        #expect(VirtualClockFormat.date(date, format: .fullDate, locale: Locale(identifier: "en_US")) == "Oct 22, 2026 Thu")
    }

    @Test func dateFormats() {
        #expect(VirtualClockFormat.date(date, format: .fullDate, locale: taiwan) == "2026年10月22日 週四")
        #expect(VirtualClockFormat.date(date, format: .slash, locale: taiwan) == "2026/10/22 週四")
        #expect(VirtualClockFormat.date(date, format: .short, locale: taiwan) == "10/22 週四")
    }
}

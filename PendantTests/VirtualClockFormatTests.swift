import Foundation
import Testing
@testable import Pendant

struct VirtualClockFormatTests {
    private var date: Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 22; parts.hour = 19; parts.minute = 5; parts.second = 9
        return Calendar(identifier: .gregorian).date(from: parts)!
    }

    private let locale = Locale(identifier: "en_US_POSIX")

    @Test func twentyFourHour() {
        #expect(VirtualClockFormat.string(for: date, use24Hour: true, seconds: false, showsDate: false, locale: locale) == "19:05")
        #expect(VirtualClockFormat.string(for: date, use24Hour: true, seconds: true, showsDate: false, locale: locale) == "19:05:09")
    }

    @Test func twelveHour() {
        #expect(VirtualClockFormat.string(for: date, use24Hour: false, seconds: false, showsDate: false, locale: locale) == "7:05 PM")
    }

    @Test func dateComesBeforeTheTime() {
        let text = VirtualClockFormat.string(for: date, use24Hour: true, seconds: false, showsDate: true, locale: locale)
        #expect(text.hasSuffix(" 19:05"))
        #expect(text.count > "19:05".count)
    }
}

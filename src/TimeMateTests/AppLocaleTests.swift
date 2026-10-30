import XCTest

@testable import TimeMate

final class AppLocaleTests: XCTestCase {
  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  func testEnglishOnA24HourMacShowsTwentyFourHourRange() {
    let base = Locale(identifier: "en_GB@hours=h23")
    let locale = AppLocale.make(language: "en", base: base)
    XCTAssertEqual(locale.hourCycle, .zeroToTwentyThree)
    let range = StatisticsFormat.hourRange(9, calendar: utc, locale: locale)
    XCTAssertEqual(range.replacingOccurrences(of: "\u{2009}", with: " "), "09:00 – 10:00")
  }

  func testKeepsSystemRegionWithAppLanguage() {
    let locale = AppLocale.make(language: "vi", base: Locale(identifier: "de_DE"))
    XCTAssertEqual(locale.language.languageCode, "vi")
    XCTAssertEqual(locale.region, "DE")
  }

  func testVietnameseUnchanged() {
    let base = Locale(identifier: "vi_VN")
    let locale = AppLocale.make(language: "vi", base: base)
    XCTAssertEqual(
      StatisticsFormat.hourRange(9, calendar: utc, locale: locale),
      StatisticsFormat.hourRange(9, calendar: utc, locale: base))
  }
}

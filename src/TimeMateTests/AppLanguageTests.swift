//  Created by homielab.com

import XCTest

@testable import TimeMate

final class AppLanguageTests: XCTestCase {
  func testStoredListMapsToPickerValue() {
    XCTAssertEqual(AppLanguage.code(fromStored: nil), "system")
    XCTAssertEqual(AppLanguage.code(fromStored: []), "system")
    XCTAssertEqual(AppLanguage.code(fromStored: ["en-US"]), "en")
    XCTAssertEqual(AppLanguage.code(fromStored: ["vi"]), "vi")
    XCTAssertEqual(AppLanguage.code(fromStored: ["fr"]), "system")
  }

  func testSavedCodeReadsTheAppDomainOnly() {
    let suite = "AppLanguageTests-\(UUID().uuidString)"
    let defaults = UserDefaults.standard
    defer { defaults.removePersistentDomain(forName: suite) }
    // Nothing stored for this domain: System Default, even though the global
    // domain (which `standard` also searches) has AppleLanguages.
    XCTAssertEqual(AppLanguage.savedCode(defaults: defaults, domain: suite), "system")
    defaults.setPersistentDomain([AppLanguage.defaultsKey: ["vi"]], forName: suite)
    XCTAssertEqual(AppLanguage.savedCode(defaults: defaults, domain: suite), "vi")
    XCTAssertEqual(AppLanguage.savedCode(defaults: defaults, domain: nil), "system")
  }

  func testAboutURLFollowsTheAppLanguage() {
    XCTAssertEqual(
      AppLanguage.aboutURL(preferredLocalizations: ["vi"])?.absoluteString,
      "https://homielab.com/vi/page/timemate")
    XCTAssertEqual(
      AppLanguage.aboutURL(preferredLocalizations: ["en"])?.absoluteString,
      "https://homielab.com/en/page/timemate")
    XCTAssertEqual(
      AppLanguage.aboutURL(preferredLocalizations: [])?.absoluteString,
      "https://homielab.com/en/page/timemate")
  }
}

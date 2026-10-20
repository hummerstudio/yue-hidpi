import XCTest
@testable import YueHiDPICore

/// The assertions themselves live in `SelfTest` so that `yue-hidpi selftest`
/// can run them on machines with Command Line Tools only (no XCTest).
/// This target exists so CI with a full Xcode toolchain also runs them.
final class SelfTestTests: XCTestCase {

    func testAllInvariants() {
        let results = SelfTest.run()
        XCTAssertFalse(results.isEmpty)
        for result in results where !result.passed {
            XCTFail("\(result.name)：\(result.detail)")
        }
    }
}

/// A few checks that need XCTest-specific helpers.
final class ExtraTests: XCTestCase {

    func testPlistIsValidPropertyList() throws {
        let document = try OverrideDocument(vendorID: 1552, productID: 0xa03e,
                                            logicalSizes: [Size2D(width: 1440, height: 900)])
        let xml = try document.xmlData()
        let object = try PropertyListSerialization.propertyList(from: xml, format: nil)
        let dictionary = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(dictionary["DisplayVendorID"] as? Int, 1552)
        XCTAssertEqual(dictionary["DisplayProductID"] as? Int, 0xa03e)
        XCTAssertEqual((dictionary["scale-resolutions"] as? [Data])?.count, 1)
    }

    func testEmptyResolutionListIsRejected() {
        XCTAssertThrowsError(try OverrideDocument(vendorID: 1, productID: 2,
                                                  logicalSizes: []))
    }
}

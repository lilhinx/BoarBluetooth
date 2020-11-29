import XCTest
@testable import BoarBluetooth

final class BoarBluetoothTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(BoarBluetooth().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}

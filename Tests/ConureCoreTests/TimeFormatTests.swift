import XCTest
@testable import ConureCore

final class TimeFormatTests: XCTestCase {
    func testClockFormatting() {
        XCTAssertEqual(TimeFormat.clock(0), "0:00:00")
        XCTAssertEqual(TimeFormat.clock(61), "0:01:01")
        XCTAssertEqual(TimeFormat.clock(3671), "1:01:11")
    }

    func testSRTTimestamp() {
        XCTAssertEqual(TimeFormat.srtTimestamp(0), "00:00:00,000")
        XCTAssertEqual(TimeFormat.srtTimestamp(3661.5), "01:01:01,500")
        XCTAssertEqual(TimeFormat.srtTimestamp(3599.999), "00:59:59,999")
    }

    func testSRTRangeEnforcesPositiveDuration() {
        XCTAssertEqual(TimeFormat.srtRange(5, 5), "00:00:05,000 --> 00:00:05,001")
        XCTAssertEqual(TimeFormat.srtRange(10, 20), "00:00:10,000 --> 00:00:20,000")
    }
}

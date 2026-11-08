import XCTest
import RegressionFixtures

final class BeatGridDetectorTests: XCTestCase {
    func testBeatGridAndTempoRegressions() async throws {
        let results = try await BeatGridFixtures.run()
        XCTAssertEqual(results.count, 4)
    }
}

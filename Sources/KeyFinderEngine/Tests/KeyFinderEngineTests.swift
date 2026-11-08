import XCTest
@testable import KeyFinderEngine
import RegressionFixtures

final class KeyFinderEngineTests: XCTestCase {
    func testDJPreparationRegressions() async throws {
        let results = try await RegressionFixtures.run()
        XCTAssertGreaterThanOrEqual(results.count, 10)
    }
}

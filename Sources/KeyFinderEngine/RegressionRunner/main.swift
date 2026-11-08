import Foundation
import RegressionFixtures

do {
    let results = try await RegressionFixtures.run()
    for result in results { print("PASS: \(result)") }
    print("\(results.count) regression groups passed.")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}

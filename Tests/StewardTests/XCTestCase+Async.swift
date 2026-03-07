import Foundation
import XCTest

extension XCTestCase {
    func waitForValue<T>(
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: (@escaping (T) -> Void) -> Void
    ) -> T {
        let callbackExpectation = expectation(description: "Await callback value")
        var output: T?

        operation { value in
            output = value
            callbackExpectation.fulfill()
        }

        wait(for: [callbackExpectation], timeout: timeout)

        guard let output else {
            XCTFail("Expected callback value.", file: file, line: line)
            fatalError("Expected callback value.")
        }

        return output
    }
}

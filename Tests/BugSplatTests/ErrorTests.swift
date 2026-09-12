import XCTest
import BugSplatNative
@testable import BugSplat

final class ErrorTests: XCTestCase {
    func testOkIsNoError() {
        XCTAssertNil(BugSplatError(BUGSPLAT_OK))
        XCTAssertNoThrow(try BugSplatError.check(BUGSPLAT_OK))
    }

    func testEveryResultMapsToACode() {
        let expectations: [(bugsplat_result, BugSplatError.Code)] = [
            (BUGSPLAT_ERR_INVALID_ARGUMENT, .invalidArgument),
            (BUGSPLAT_ERR_ALREADY_INITIALIZED, .alreadyStarted),
            (BUGSPLAT_ERR_NOT_INITIALIZED, .notStarted),
            (BUGSPLAT_ERR_MONITOR_NOT_FOUND, .monitorNotFound),
            (BUGSPLAT_ERR_MONITOR_START_FAILED, .monitorStartFailed),
            (BUGSPLAT_ERR_REPORTER_NOT_FOUND, .reporterNotFound),
            (BUGSPLAT_ERR_IO, .io),
            (BUGSPLAT_ERR_LIMIT_EXCEEDED, .limitExceeded),
            (BUGSPLAT_ERR_UNSUPPORTED, .unsupported),
            (BUGSPLAT_ERR_NETWORK, .network),
            (BUGSPLAT_ERR_HTTP, .http),
            (BUGSPLAT_ERR_REJECTED, .rejected),
            (BUGSPLAT_ERR_CANCELLED, .cancelled),
            (BUGSPLAT_ERR_INTERNAL, .internalError),
        ]
        for (result, code) in expectations {
            XCTAssertEqual(BugSplatError(result)?.code, code, "\(result)")
        }
        XCTAssertEqual(BugSplatError.Code.allCases.count, expectations.count, "every ABI result has a Swift code")
    }

    func testNSErrorBridging() {
        let error = BugSplatError(BUGSPLAT_ERR_HTTP, httpStatus: 503)!
        let ns = error as NSError
        XCTAssertEqual(ns.domain, "com.bugsplat.BugSplat")
        XCTAssertEqual(ns.code, 11)
        XCTAssertEqual(ns.userInfo["httpStatus"] as? Int, 503)
        XCTAssertTrue(ns.localizedDescription.contains("503"))
        XCTAssertEqual(error.errorDescription, error.description)
    }

    func testDescriptionsAreHuman() {
        for code in BugSplatError.Code.allCases {
            let text = BugSplatError(code: code).description
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("BUGSPLAT_ERR"), "no raw enum names in user-facing text")
        }
    }
}

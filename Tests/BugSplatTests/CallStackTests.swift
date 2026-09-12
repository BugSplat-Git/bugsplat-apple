import XCTest
@testable import BugSplat

final class CallStackTests: XCTestCase {
    func testParsesSymbolLines() throws {
        let lines = [
            "0   BugSplat                            0x0000000104a1c2f0 $s8BugSplat6ReportC5error6formatACs5Error_p_AA0E6FormatOtcfc + 212",
            "1   MyApp                               0x0000000102f5a3b4 $s5MyApp9ViewModelC4loadyyF + 24",
            "2   libdyld.dylib                       0x00000001a3c2d0f4 start + 520",
            "garbage line",
        ]
        let frames = CallStackSymbols.parse(lines)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].module, "BugSplat")
        XCTAssertEqual(frames[1].index, 1)
        XCTAssertEqual(frames[1].module, "MyApp")
        XCTAssertEqual(frames[1].address, 0x0000000102f5a3b4)
        XCTAssertEqual(frames[1].symbol, "$s5MyApp9ViewModelC4loadyyF")
        XCTAssertEqual(frames[1].offset, 24)
        XCTAssertEqual(frames[2].symbol, "start")
    }

    func testMissingSymbolFallsBackToAddress() throws {
        let frame = try XCTUnwrap(CallStackSymbols.parse("7   ???                                 0x00000001000012ab 0x0 + 4294971051"))
        XCTAssertEqual(frame.module, "???")
        XCTAssertEqual(frame.symbol, "0x0")
    }

    func testReportFromErrorBuildsWithoutStart() {
        // Building never touches the session; only posting does.
        struct Boom: Error {}
        let report = BugSplat.Report(error: Boom(), callStack: [
            "0   BugSplat   0x0000000104a1c2f0 $s8BugSplat_internal + 1",
            "1   MyApp      0x0000000102f5a3b4 $s5MyApp4mainyyF + 24",
        ])
        XCTAssertNotNil(report)
    }

    func testLiveCallStackParses() {
        let frames = CallStackSymbols.parse(Thread.callStackSymbols)
        XCTAssertFalse(frames.isEmpty)
        XCTAssertTrue(frames.contains { $0.module.contains("BugSplatTests") || $0.module.contains("xctest") || $0.module.contains("XCTest") })
    }
}

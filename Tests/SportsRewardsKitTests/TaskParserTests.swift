import XCTest
@testable import SportsRewardsKit

/// 驗證 TaskParser 對 `/member/tasks` 頁面的解析：14 期、第 1 期 redeemable 且有 uuid，其餘 notStarted。
final class TaskParserTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures") else {
            XCTFail("fixture \(name).html not found in bundle")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParseReturnsFourteenPeriods() throws {
        // Arrange
        let html = try loadFixture("member_tasks")

        // Act
        let periods = try TaskParser.parse(html: html)

        // Assert
        XCTAssertEqual(periods.count, 14)
    }

    func testFirstPeriodIsRedeemableWithNonEmptyID() throws {
        // Arrange
        let html = try loadFixture("member_tasks")

        // Act
        let periods = try TaskParser.parse(html: html)
        let first = try XCTUnwrap(periods.first)

        // Assert
        XCTAssertEqual(first.index, 1)
        XCTAssertEqual(first.state, .redeemable)
        XCTAssertFalse(first.id.isEmpty)
        XCTAssertEqual(first.id, "9f746d24-213d-43c8-b291-5183cab4c64f")
        XCTAssertEqual(first.startDate, "2026/09/01")
        XCTAssertEqual(first.endDate, "2026/09/06")
        XCTAssertEqual(first.remainingText, "剩 1 天 22 小時")
        XCTAssertEqual(first.uploadedAt, "2026/09/03 21:42")
        XCTAssertEqual(first.reviewedAt, "2026/09/04 20:10")
    }

    func testRemainingPeriodsAreNotStartedWithEmptyID() throws {
        // Arrange
        let html = try loadFixture("member_tasks")

        // Act
        let periods = try TaskParser.parse(html: html)

        // Assert
        let rest = periods.dropFirst()
        XCTAssertEqual(rest.count, 13)
        for period in rest {
            XCTAssertEqual(period.state, .notStarted, "period \(period.index) should be notStarted")
            XCTAssertTrue(period.id.isEmpty, "period \(period.index) should have no uuid")
        }
    }

    func testPeriodIndicesAreSequential() throws {
        // Arrange
        let html = try loadFixture("member_tasks")

        // Act
        let periods = try TaskParser.parse(html: html)

        // Assert
        XCTAssertEqual(periods.map(\.index), Array(1...14))
    }

    func testParseThrowsWhenNoPeriodCardFound() {
        // Arrange
        let html = "<html><body><p>no cards here</p></body></html>"

        // Act & Assert
        XCTAssertThrowsError(try TaskParser.parse(html: html)) { error in
            XCTAssertEqual(error as? AppError, .parsing("no period-card found in /member/tasks HTML"))
        }
    }

    func testNotUploadedMapsToOpen() throws {
        // 實測形狀：當期尚未上傳 = period-state--NOT_UPLOADED，應對到 .open（可上傳）。
        let html = """
        <ul class="period-list">
        <li class="period-card period-card--current">
        <span class="period-no">第 1 期</span>
        <span class="period-range">2026/09/01 ~ 2026/09/06</span>
        <span class="period-remaining">剩 1 天 12 小時</span>
        <p class="period-state period-state--NOT_UPLOADED"><span>尚未上傳</span></p>
        <div class="period-actions"><a href="/registrant/member/upload" class="btn btn--primary">上傳運動紀錄</a></div>
        </li>
        </ul>
        """
        let periods = try TaskParser.parse(html: html)
        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods[0].state, .open)
        XCTAssertEqual(periods[0].index, 1)
    }


    func testUnderReviewMapsToPendingReview() throws {
        // 實測：上傳後待審核的真實 class 是 UNDER_REVIEW。
        let html = """
        <ul class="period-list">
        <li class="period-card">
        <span class="period-no">第 1 期</span>
        <span class="period-range">2026/09/01 ~ 2026/09/06</span>
        <p class="period-state period-state--UNDER_REVIEW"><span>待審核</span></p>
        </li>
        </ul>
        """
        let periods = try TaskParser.parse(html: html)
        XCTAssertEqual(periods.first?.state, .pendingReview)
    }

}

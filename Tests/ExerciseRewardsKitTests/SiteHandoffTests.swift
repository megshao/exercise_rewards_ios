import XCTest
@testable import ExerciseRewardsKit

/// 驗證 `SiteHandoff`：官網改版時交接到官網的 URL 組法、`taskID` 白名單、以及哪些錯誤該走接手畫面。
/// 純函式，不打網路。
final class SiteHandoffTests: XCTestCase {
    private let taskID = "00000000-0000-4000-8000-000000000001"

    // MARK: - 三種目的地的完整 URL

    func testTasksURL() {
        XCTAssertEqual(SiteHandoff.url(for: .tasks).absoluteString,
                       "https://500.gov.tw/registrant/member/tasks")
    }

    func testRedeemURLWithValidTaskID() {
        XCTAssertEqual(SiteHandoff.url(for: .redeem(taskID: taskID)).absoluteString,
                       "https://500.gov.tw/registrant/member/redeem/\(taskID)")
    }

    func testVoucherURLWithValidTaskID() {
        XCTAssertEqual(SiteHandoff.url(for: .voucher(taskID: taskID)).absoluteString,
                       "https://500.gov.tw/registrant/member/voucher/\(taskID)")
    }

    // MARK: - 一律 https、一律 500.gov.tw

    func testEveryDestinationIsHTTPSOnOfficialHost() {
        let destinations: [SiteHandoffDestination] = [
            .tasks,
            .redeem(taskID: taskID),
            .voucher(taskID: taskID),
            // 退回 `.tasks` 的路徑也要滿足同一條件。
            .redeem(taskID: "../../login"),
            .voucher(taskID: ""),
        ]
        for destination in destinations {
            let url = SiteHandoff.url(for: destination)
            XCTAssertEqual(url.scheme, "https", "\(destination)")
            XCTAssertEqual(url.host, SiteConfig.host, "\(destination)")
            XCTAssertTrue(url.absoluteString.hasPrefix(SiteConfig.base + "/"), "\(destination)")
        }
    }

    // MARK: - taskID 是不受信任輸入：驗證失敗一律退回 .tasks

    /// 空／路徑穿越／query／fragment／空白／百分比編碼的 `..`／過長，每一種都不能組出
    /// 越界路徑，也不能讓按鈕消失——所以答案一律是任務清單頁。
    func testInvalidTaskIDsFallBackToTasks() {
        let tasksURL = SiteHandoff.url(for: .tasks)
        let invalid: [String] = [
            "",
            "   ",
            "../../login",
            "abc/../../logout",
            "abc?next=https://evil.example",
            "abc#fragment",
            "ab cd",
            "%2e%2e%2f",
            "abc%2f..%2fx",
            "abc.html",
            "abc_def",                                  // 底線不在 parser 的字元集內
            "demo-period-01",                           // 非十六進位字母也不在（示範 id；示範模式不顯示按鈕）
            "g0000000-0000-4000-8000-000000000001",
            String(repeating: "a", count: SiteHandoff.maxTaskIDLength + 1),
            "00000000-0000-4000-8000-000000000001\n",  // 換行不算 trim 得掉的東西
        ]
        for taskID in invalid {
            XCTAssertEqual(SiteHandoff.url(for: .redeem(taskID: taskID)), tasksURL,
                           "redeem should fall back for \(taskID.debugDescription)")
            XCTAssertEqual(SiteHandoff.url(for: .voucher(taskID: taskID)), tasksURL,
                           "voucher should fall back for \(taskID.debugDescription)")
        }
    }

    func testFallbackURLNeverContainsTraversalOrQuery() {
        for taskID in ["../../login", "%2e%2e", "x?y=z", "x#y"] {
            for url in [SiteHandoff.url(for: .redeem(taskID: taskID)),
                        SiteHandoff.url(for: .voucher(taskID: taskID))] {
                XCTAssertFalse(url.path.contains(".."), url.absoluteString)
                XCTAssertNil(url.query, url.absoluteString)
                XCTAssertNil(url.fragment, url.absoluteString)
                XCTAssertEqual(url.path, "/registrant/member/tasks", url.absoluteString)
            }
        }
    }

    // MARK: - 合法 uuid：路徑正確且未被重複編碼

    func testValidTaskIDIsNotPercentEncoded() {
        let url = SiteHandoff.url(for: .redeem(taskID: taskID))
        XCTAssertEqual(url.path, "/registrant/member/redeem/\(taskID)")
        XCTAssertEqual(url.lastPathComponent, taskID)
        XCTAssertFalse(url.absoluteString.contains("%"), url.absoluteString)
    }

    func testTaskIDAtMaxLengthIsAccepted() {
        let longest = String(repeating: "f", count: SiteHandoff.maxTaskIDLength)
        XCTAssertEqual(SiteHandoff.url(for: .voucher(taskID: longest)).lastPathComponent, longest)
    }

    /// 大小寫十六進位都收，跟 `TaskParser.idPattern` 一樣。
    func testUppercaseHexTaskIDIsAccepted() {
        XCTAssertEqual(SiteHandoff.url(for: .redeem(taskID: "ABCDEF-0123")).lastPathComponent, "ABCDEF-0123")
    }

    func testIsValidTaskIDMirrorsURLFallback() {
        XCTAssertTrue(SiteHandoff.isValidTaskID(taskID))
        XCTAssertTrue(SiteHandoff.isValidTaskID("ABCDEF-0123"))
        XCTAssertFalse(SiteHandoff.isValidTaskID("demo-period-01"))
        XCTAssertFalse(SiteHandoff.isValidTaskID(""))
        XCTAssertFalse(SiteHandoff.isValidTaskID(" \(taskID)"))
        XCTAssertFalse(SiteHandoff.isValidTaskID("\(taskID)/view"))
    }

    // MARK: - 觸發條件分流

    func testParsingAndCsrfNotFoundTriggerHandoff() {
        XCTAssertTrue(SiteHandoff.shouldHandoff(AppError.parsing("no period-card found")))
        XCTAssertTrue(SiteHandoff.shouldHandoff(AppError.parsing("")))
        XCTAssertTrue(SiteHandoff.shouldHandoff(AppError.csrfNotFound))
    }

    func testOtherAppErrorsDoNotTriggerHandoff() {
        let notTriggering: [AppError] = [
            .network("code -1009"),
            .unexpectedResponse(500),
            .unexpectedResponse(-1),
            .notLoggedIn,
            .blockedEgress("attacker.example"),
            .responseTooLarge(3_000_000),
        ]
        for error in notTriggering {
            XCTAssertFalse(SiteHandoff.shouldHandoff(error), "\(error)")
        }
    }

    func testNonAppErrorsDoNotTriggerHandoff() {
        struct SomethingElse: Error {}
        XCTAssertFalse(SiteHandoff.shouldHandoff(SomethingElse()))
        XCTAssertFalse(SiteHandoff.shouldHandoff(URLError(.notConnectedToInternet)))
    }

    // MARK: - 端到端：券夾／任務頁那條路

    /// 首頁、任務頁、券夾都是 `TasksService.fetchTasks()` → `TaskParser.parse`。官網改版（或 302 回登入頁）
    /// 時 parser 丟 `.parsing`，這條錯誤一路傳到 ViewModel 的 catch，那裡就是靠 `shouldHandoff` 分流。
    /// 這裡把整條路串起來測：改版頁面 → 接手；網路錯誤 → 不接手。
    func testFetchTasksOnChangedPageIsHandedOff() async {
        let mock = MockHTTPClient()
        mock.htmlByPath["/member/tasks"] = "<html><body><h1>全新改版的任務頁</h1></body></html>"
        let sut = TasksService(http: mock)

        do {
            _ = try await sut.fetchTasks()
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(SiteHandoff.shouldHandoff(error), "\(error)")
        }
    }

    func testFetchTasksNetworkFailureIsNotHandedOff() async {
        // 未程式化任何 path：MockHTTPClient 丟 `unexpectedResponse(404)`，等同官網回錯誤狀態碼。
        let sut = TasksService(http: MockHTTPClient())

        do {
            _ = try await sut.fetchTasks()
            XCTFail("expected throw")
        } catch {
            XCTAssertFalse(SiteHandoff.shouldHandoff(error), "\(error)")
        }
    }
}

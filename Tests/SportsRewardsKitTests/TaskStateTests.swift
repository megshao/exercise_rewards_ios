import XCTest
@testable import SportsRewardsKit

/// 驗證 `TaskState.showsUploadCountdown`。
///
/// 這條規則存在的理由是一個實測事實：官網的 `period-remaining` 是**上傳窗**倒數
/// （「本期任務可上傳時間 剩 N 小時 N 分」），而且**對已經走完審核的期別照樣回傳**。
/// 2026-09-06 實測一張已兌換的券，卡片上仍寫著那句話。
///
/// 因此這裡守的不是排版偏好，而是「哪些狀態下官網給的那個數字已經沒有意義」。
final class TaskStateTests: XCTestCase {
    /// 審核完成之後（可兌換／已兌換）上傳早就做完了，倒數指的是一個用不到的窗。
    func testHidesUploadCountdownAfterReviewIsComplete() {
        XCTAssertFalse(TaskState.redeemable.showsUploadCountdown)
        XCTAssertFalse(TaskState.redeemed.showsUploadCountdown)
    }

    /// 上傳窗還可能用得到的狀態一律保留。
    func testShowsUploadCountdownWhileUploadWindowStillMatters() {
        XCTAssertTrue(TaskState.notStarted.showsUploadCountdown)
        XCTAssertTrue(TaskState.open.showsUploadCountdown)
        XCTAssertTrue(TaskState.pendingReview.showsUploadCountdown)
    }

    /// 認不出來的狀態保守處理：照顯示，不要把官網給的資訊悄悄吃掉。
    func testUnknownStateKeepsShowingWhateverTheSiteSent() {
        XCTAssertTrue(TaskState.unknown.showsUploadCountdown)
    }

    /// 新增狀態時這個測試會失敗，提醒作者去決定新狀態該落在哪一邊——
    /// 而不是讓它默默沿用 switch 的某個分支。
    func testEveryStateIsClassifiedDeliberately() {
        let hidden: Set<TaskState> = [.redeemable, .redeemed]
        let shown: Set<TaskState> = [.notStarted, .open, .pendingReview, .unknown]

        XCTAssertTrue(hidden.isDisjoint(with: shown))
        XCTAssertEqual(hidden.count + shown.count, 6,
                       "TaskState 有新成員時，請先決定它要不要顯示上傳窗倒數")
        for state in hidden { XCTAssertFalse(state.showsUploadCountdown, "\(state)") }
        for state in shown { XCTAssertTrue(state.showsUploadCountdown, "\(state)") }
    }
}

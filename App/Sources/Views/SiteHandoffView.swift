import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ExerciseRewardsKit

// MARK: - 官網改版降級接手（Site-change handoff）
//
// 這支 App 完全靠手寫 regex 解析 500.gov.tw 的 HTML。官網一改版，所有已安裝版本同時失效，
// 修好、送審、上架要好幾天。在那之前，使用者看到的不該是「請確認網路連線」——那會讓人去
// 重開 Wi-Fi，比壞掉更傷信任。
//
// 這裡的三塊 UI 只做一件事：**說實話並交接**。告訴使用者「App 讀不到官網這一頁，可能是官網
// 改版了」，給一顆「前往官網」外開系統瀏覽器到對應頁面，再給一顆「複製身分證號」讓他在官網
// 少打一欄。不修 parser、不繞改版、不做 WebView、不自動登入（理由見 Kit 的 `SiteHandoff`）。
//
// 哪些錯誤該走這裡、URL 怎麼組，都在 Kit 的 `SiteHandoff`（有單元測試）。這個檔案只負責呈現與
// 開啟：**不要在這裡拼任何 URL 字串**。

/// 「前往官網」的唯一出口。集中在一處，示範／截圖模式的守衛才只寫一次。
/// `@MainActor`：`OpenURLAction` 是主執行緒限定，而呼叫端本來就全是 View。
@MainActor
enum SiteHandoffOpener {
    /// 示範模式與截圖模式下**不顯示「前往官網」**（與 Android 一致，也與 §5c 對複製按鈕的做法一致）：
    /// - 示範模式的橫幅寫著「未連線官方網站」，把審查員丟到 Safari 的 500.gov.tw 會讓那句話變模糊。
    /// - 截圖流程（`App/UITests/ScreenshotTests.swift`）跳出 App 就拍不下去了。
    /// 實務上示範模式的 `Mock*Service` 不會丟解析錯誤，接手畫面在示範流程中本來就不會出現，
    /// 這道守衛是雙保險。`open` 內再擋一次，讓「按鈕沒藏好」也不會真的開出去。
    static var isBrowserAllowed: Bool {
        !DemoMode.isActive && !ScreenshotMode.isEnabled
    }

    /// 外開系統瀏覽器到官網對應頁面。做法照 `OnboardingView` 的「前往官網註冊」：
    /// `openURL`，不用 WebView，維持零 WebKit 依賴。
    static func open(_ destination: SiteHandoffDestination, with openURL: OpenURLAction) {
        guard isBrowserAllowed else { return }
        openURL(SiteHandoff.url(for: destination))
    }
}

/// 沒有可顯示資料時的全屏狀態：標題、說明、前往官網、複製身分證號、重新載入。
///
/// 取代各頁原本「無法載入…請確認網路連線」的錯誤分支——**只在** `SiteHandoff.shouldHandoff(_:)`
/// 為真時使用；網路錯誤等其他情境照舊走各頁原本的 `errorState`，那些文案在它們的情境下是對的。
struct SiteHandoffState: View {
    let destination: SiteHandoffDestination
    /// 說明文字。預設是通用版；券碼頁要換成貼合「站在櫃檯前」情境的那一句（見 `VoucherView`）。
    var message: String = SiteHandoffState.defaultMessage
    /// 「重新載入」按鈕的文字。券碼頁沒有東西可以重抓，改成「返回重試」。
    var refreshTitle: String = "重新載入"
    /// 保留既有的重新整理入口。nil 就不顯示那顆按鈕。
    var onRefresh: (() async -> Void)? = nil

    static let defaultMessage =
        "這支 App 讀不到官網這個頁面的資料，可能是官網改版了。你可以先到官網完成，我們會盡快修正。"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.danger)
                    .font(.system(size: 20))
                Text("官網可能已改版")
                    .font(Theme.displayFont(17, weight: .bold))
                    .foregroundStyle(Theme.Colors.text)
            }

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)

            SiteHandoffActions(destination: destination)

            if let onRefresh {
                Button {
                    Task { await onRefresh() }
                } label: {
                    Text(refreshTitle)
                }
                .buttonStyle(.huihanSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// 有快取可顯示時的頂端 banner：照舊顯示資料，只在上面加一條「這是先前抓到的」。
///
/// 樣式沿用 `DemoModeBanner`（深底白字一條），不另創視覺語言。差別只有兩個：多了「前往官網」
/// 與關閉鈕；以及不 `ignoresSafeArea`——它掛在導覽列下面，不在視窗最頂端。
///
/// 關掉之後由呼叫端的 ViewModel 記住；**下一次抓取再失敗時要重新出現**（各 ViewModel 在
/// 每次抓取開頭把 dismissed 歸零）。
struct SiteHandoffBanner: View {
    let destination: SiteHandoffDestination
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
            Text("官網可能已改版，以下是先前抓到的資料")
                .font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if SiteHandoffOpener.isBrowserAllowed {
                Button {
                    SiteHandoffOpener.open(destination, with: openURL)
                } label: {
                    Text("前往官網")
                        .font(.system(size: 12, weight: .bold))
                        .underline()
                }
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("關閉提示")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.text)
    }
}

/// 「前往官網」＋「複製身分證號」兩顆按鈕與剪貼簿提示。全屏狀態用；banner 只放前者。
private struct SiteHandoffActions: View {
    let destination: SiteHandoffDestination

    @Environment(\.appEnvironment) private var environment
    @Environment(\.openURL) private var openURL
    /// 可以複製的身分證號。nil 就不顯示那顆按鈕（還沒填個資、讀不到 Keychain、或示範模式）。
    @State private var copyableIDNo: String?
    @State private var didCopy = false

    /// 剪貼簿內容的存活時間。使用者要外開瀏覽器、找到登入頁、點進欄位再貼上，
    /// 一分鐘太趕；三分鐘夠用，之後系統自動清掉，不讓身分證號無限期留在剪貼簿。
    private static let clipboardLifetime: TimeInterval = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if SiteHandoffOpener.isBrowserAllowed {
                Button {
                    SiteHandoffOpener.open(destination, with: openURL)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "safari")
                        Text("前往官網")
                    }
                }
                .buttonStyle(.huihanPrimary)
                .accessibilityIdentifier("siteHandoffOpenSite")
            }

            if let idNo = copyableIDNo {
                Button {
                    copy(idNo)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        Text(didCopy ? "已複製" : "複製身分證號")
                    }
                }
                .buttonStyle(.huihanSecondary)
                .accessibilityIdentifier("siteHandoffCopyIDNo")

                // §6 的揭露：剪貼簿是所有 App 共用的，這是一條新的資料路徑，要在按鈕旁邊講清楚。
                Text("只複製身分證號；會留在這支手機的剪貼簿約 3 分鐘，不同步到其他裝置。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Colors.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { copyableIDNo = loadCopyableIDNo() }
    }

    /// 從既有的個資儲存（Keychain）讀身分證號。**只讀這一欄**——生日與手機使用者自己知道，
    /// 也刻意不一次把三碼都攤在剪貼簿上。
    ///
    /// 示範模式下回 nil：`InMemoryProfileStore` 裡的是哨兵值 `A000000000`，
    /// 不該被複製到剪貼簿。最後再比對一次哨兵值是雙保險，不靠旗標一個人守。
    private func loadCopyableIDNo() -> String? {
        guard !DemoMode.isActive,
              let profile = try? environment.profileStore.load() else { return nil }
        let idNo = profile.idNo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idNo.isEmpty,
              idNo.caseInsensitiveCompare(DemoMode.idNo) != .orderedSame else { return nil }
        return idNo
    }

    /// 寫進剪貼簿。兩個選項都是刻意的：
    /// - `.localOnly`：不進 Universal Clipboard，身分證號不會被同步到使用者的其他 Apple 裝置。
    /// - `.expirationDate`：到時系統自動清掉，不必依賴使用者記得去覆蓋。
    /// 這顆按鈕不送任何遙測——複製這個動作本身就足以推論使用者正在處理個資。
    private func copy(_ idNo: String) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: idNo]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(Self.clipboardLifetime),
            ]
        )
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}

// MARK: - Preview

#Preview("全屏狀態 / banner") {
    VStack(spacing: 0) {
        SiteHandoffBanner(destination: .tasks, onDismiss: {})
        ScrollView {
            VStack(spacing: 16) {
                SiteHandoffState(destination: .tasks, onRefresh: {})
                SiteHandoffState(
                    destination: .voucher(taskID: "demo-period-01"),
                    message: "這支 App 讀不到官網的券碼頁，可能是官網改版了。請到官網檢視加碼券——券碼要在官網重新驗證一次簡訊才會顯示。",
                    refreshTitle: "返回重試",
                    onRefresh: {}
                )
            }
            .padding(20)
        }
    }
    .background(Theme.Colors.background)
    // 預覽用注入版環境而不是 `DemoMode.makeEnvironment()`：後者不會把 `demoModeEnabled` 寫進
    // UserDefaults，所以按鈕照常顯示；但語意上這裡不是示範模式，別讓人誤會。
    .environment(\.appEnvironment, DefaultAppEnvironment(
        auth: MockAuthService(), tasks: MockTasksService(), redeem: MockRedeemService(),
        voucher: MockVoucherService(), profileStore: InMemoryProfileStore(seed: Profile(idNo: "A123456789"))
    ))
}

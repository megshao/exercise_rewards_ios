import SwiftUI
import ExerciseRewardsKit

/// 我的任務儀表板：垂直卡片列出 [TaskPeriod]，本週置頂高亮，下拉刷新。
/// 對齊設計稿。
struct TasksView: View {
    @Environment(\.appEnvironment) private var environment
    /// 「已使用」標記的共用真相來源。**這一頁踩過的坑**：先前 ViewModel 各自抄一份，
    /// 在券夾標記完切回這頁就不會更新，連下拉重新整理都沒用——因為下拉只重抓官網資料，
    /// 而「已使用」根本不在官網資料裡（見 `VoucherUsageStore`）。
    @EnvironmentObject private var voucherUsage: VoucherUsageStore
    @StateObject private var viewModel = TasksViewModel()
    @State private var screenshotPeriod: TaskPeriod?
    @State private var redeemPeriod: TaskPeriod?
    @State private var voucherPeriod: TaskPeriod?
    @State private var uploadPeriod: TaskPeriod?

    var body: some View {
        VStack(spacing: 0) {
            // 5b：有快取可顯示時不蓋掉資料，只在頂端掛一條 banner 說「這是先前抓到的」。
            // 放在 ScrollView 外面才能滿版、不跟著內容捲走，位置比照 `DemoModeBanner`。
            if viewModel.showsSiteHandoffBanner {
                SiteHandoffBanner(destination: .tasks) {
                    viewModel.isSiteHandoffBannerDismissed = true
                }
            }
            scrollContent
        }
        .background(Theme.Colors.background)
        .navigationTitle("我的任務")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Telemetry.screenAppeared(.tasks) }
        .task {
            viewModel.configure(tasks: environment.tasks)
            if viewModel.periods.isEmpty {
                await viewModel.refresh()
            }
        }
        .sheet(item: $screenshotPeriod) { period in
            NavigationStack {
                ScreenshotView(taskID: period.id)
            }
            .environment(\.appEnvironment, environment)
        }
        .sheet(item: $redeemPeriod, onDismiss: {
            // 與上傳同一個模式：兌換成功後官網會改成 REDEEMED，不重抓就會停在「可兌換」。
            Task { await viewModel.refresh(force: true) }
        }) { period in
            NavigationStack {
                RedeemView(taskID: period.id, periodIndex: period.index)
            }
            .environment(\.appEnvironment, environment)
            // RedeemView 兌換成功後會再開 VoucherView，那一頁要 voucherUsage。
            .environmentObject(voucherUsage)
        }
        // 不需要 onDismiss 重讀標記：`voucherUsage` 是共用的 `@Published`，
        // 不論在哪一頁寫入，這一頁都會立刻重畫。
        .sheet(item: $voucherPeriod) { period in
            NavigationStack {
                VoucherView(taskID: period.id, source: .tasks, periodIndex: period.index)
            }
            .environment(\.appEnvironment, environment)
            .environmentObject(voucherUsage)
        }
        .sheet(item: $uploadPeriod, onDismiss: {
            // 上傳成功後官網會把該期改成 UNDER_REVIEW，但 App 這邊不會自己知道。
            // 沒有這一行，徽章會一直停在「未上傳」——而且因為首頁與這裡共用同一個
            // 節流時鐘，連下拉刷新都可能被擋掉，使用者無從自救。
            Task { await viewModel.refresh(force: true) }
        }) { period in
            NavigationStack {
                UploadView(taskID: period.id, periodIndex: period.index)
            }
            .environment(\.appEnvironment, environment)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if viewModel.isLoading && viewModel.periods.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if viewModel.isSiteHandoff, viewModel.periods.isEmpty {
                    // 5a：官網結構對不上、又沒有快取——說實話並交接，而不是叫人去檢查網路。
                    SiteHandoffState(destination: .tasks) {
                        await viewModel.refresh(force: true)
                    }
                } else if let errorMessage = viewModel.errorMessage, viewModel.periods.isEmpty {
                    errorState(errorMessage)
                } else {
                    ForEach(viewModel.periods, id: \.index) { period in
                        TaskPeriodCard(
                            period: period,
                            isHighlighted: period.index == viewModel.highlightedPeriodIndex,
                            // 標記過已使用的券不再提供「檢視加碼券」（見 VoucherUsage）。
                            isVoucherUsed: voucherUsage.isUsed(period),
                            // 兌換本身在 RedeemView 有「確認兌換」二次確認，這裡不再多一道驗證。
                            onRedeemTap: { redeemPeriod = period },
                            onScreenshotTap: { screenshotPeriod = period },
                            onVoucherTap: { voucherPeriod = period },
                            onUploadTap: { uploadPeriod = period }
                        )
                    }
                }
            }
            .padding(20)
        }
        .refreshable {
            // 下拉是使用者的明確意圖，一律真的打網路。節流只該擋自動觸發的抓取——
            // 否則轉圈動畫照跑、正常結束，看起來像刷新過了，實際什麼都沒做。
            await viewModel.refresh(force: true)
        }
    }

    private var header: some View {
        Text("每期七天，完成運動上傳並通過審核，即可換一張加碼券")
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.Colors.muted)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.danger)
                .font(.system(size: 28))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.refresh(force: true) }
            } label: {
                Text("重新載入")
            }
            .buttonStyle(.huihanSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// 單一期別卡片，本週（highlighted）用琥珀色雙邊線 + 陰影強調。
private struct TaskPeriodCard: View {
    let period: TaskPeriod
    let isHighlighted: Bool
    /// 使用者是否已在 App 內把這期的券標記為「已使用」（本機狀態）。
    let isVoucherUsed: Bool
    let onRedeemTap: () -> Void
    let onScreenshotTap: () -> Void
    let onVoucherTap: () -> Void
    let onUploadTap: () -> Void
    /// 判斷「這一期是否已經過完」的基準時間。預設當下，預覽與測試可注入固定時間。
    var now: Date = Date()

    /// 上傳窗已經過完。官網對這種卡片照樣回 `NOT_UPLOADED`（→ `.open`）且照樣附倒數字串，
    /// 所以「還能不能上傳」不能只看 state——見 `TaskPeriod.hasEnded(now:)`。
    private var hasEnded: Bool { period.hasEnded(now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text("第 \(period.index) 期")
                        .font(Theme.displayFont(15, weight: .bold))
                        .foregroundStyle(period.state == .notStarted ? Theme.Colors.dim : Theme.Colors.text)
                    Text("\(period.startDate) ~ \(period.endDate)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.muted)
                }
                Spacer()
                // 官網對已走完審核的期別（可兌換／已兌換）照樣回傳上傳窗倒數，
                // 顯示出來會讓人以為還有東西要上傳——見 `TaskState.showsUploadCountdown`。
                if showsRemaining, let remainingText = period.remainingText {
                    Text(remainingText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Colors.primaryDark)
                } else {
                    TaskStateBadge(state: period.state, hasEnded: hasEnded)
                }
            }

            // 上面那格被倒數佔走時，徽章補在下一行；沒被佔走就不用重複顯示。
            if showsRemaining, period.remainingText != nil {
                TaskStateBadge(state: period.state, hasEnded: hasEnded)
            }

            // 官網卡片上的「兌換內容：通路／品項」。官網原文，只顯示、不進遙測。
            if let summary = period.voucherSummary {
                Text("兌換內容：\(summary)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isVoucherUsed {
                Text("你已在 App 內標記為使用完畢（本機紀錄顯示，使用與否以條碼能否使用為主）。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Colors.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let uploadedAt = period.uploadedAt {
                Text(reviewSummary(uploadedAt: uploadedAt, reviewedAt: period.reviewedAt))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.muted)
            } else if period.state == .pendingReview, let remainingText = period.remainingText,
                      !isHighlighted {
                Text(remainingText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.dim)
            }

            actionRow
        }
        .padding(16)
        .background(period.state == .notStarted ? Color(hex: 0xFAFBFC) : Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(isHighlighted ? Theme.Colors.amber : Theme.Colors.line, lineWidth: isHighlighted ? 2 : 1)
        )
        .shadow(color: Color.black.opacity(isHighlighted ? 0.08 : 0.04), radius: isHighlighted ? 20 : 10, x: 0, y: isHighlighted ? 10 : 4)
    }

    /// 這張卡要不要在右上角顯示倒數：只有本週高亮、而且該狀態的倒數還有意義時才顯示。
    // 已經過完的期別不顯示倒數：官網對過期卡片仍會回「剩 N 小時」，那是一個早就關掉的窗。
    private var showsRemaining: Bool { isHighlighted && period.state.showsUploadCountdown && !hasEnded }

    private func reviewSummary(uploadedAt: String, reviewedAt: String?) -> String {
        if let reviewedAt {
            return "上傳 \(uploadedAt) · 審核 \(reviewedAt)"
        }
        return "上傳 \(uploadedAt)"
    }

    /// 非當期的卡片後端沒有 UUID（`period.id` 為空字串），「立即兌換」/「看截圖」都需要
    /// 打帶 UUID 的端點，因此一律先檢查 `hasID` 才顯示這兩顆按鈕。
    private var hasID: Bool { !period.id.isEmpty }

    @ViewBuilder
    private var actionRow: some View {
        switch period.state {
        case .redeemable:
            if hasID {
                HStack(spacing: 10) {
                    Button {
                        onRedeemTap()
                    } label: {
                        Text("立即兌換")
                    }
                    .buttonStyle(.huihanPrimary)

                    Button {
                        onScreenshotTap()
                    } label: {
                        Text("看截圖")
                    }
                    .buttonStyle(.huihanSecondary)
                }
            }
        case .open:
            // 「還能不能上傳」是狀態與日曆的合取，規則與踩過的坑都在
            // `TaskPeriod.canUpload(now:)`——那條規則刻意放在 Kit，因為 App target 沒有單元
            // 測試 target，寫在這個 private 卡片裡的判斷沒有任何測試搆得到（示範資料裡也沒有
            // 「已過期但仍 `.open`」的期別，UI 測試同樣驗不到）。這裡只負責二選一。
            if period.canUpload(now: now) {
                Button {
                    onUploadTap()
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("上傳運動紀錄")
                    }
                }
                .buttonStyle(.huihanPrimary)
            } else {
                Text("本期上傳期間已結束")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.dim)
            }
        case .redeemed, .pendingReview:
            // 已兌換／審核中：只提供「看截圖」回顧當時上傳的內容，不再提供「立即兌換」
            // （已兌換過的期別無法重複兌換；審核中則尚未進入可兌換狀態）。
            // 已兌換再加一顆「檢視加碼券」——每次點都會重新走一次簡訊 OTP（見 VoucherView）。
            if hasID && (period.state == .redeemed || period.uploadedAt != nil) {
                HStack(spacing: 10) {
                    Button {
                        onScreenshotTap()
                    } label: {
                        Text("看截圖")
                    }
                    .buttonStyle(.huihanSecondary)

                    // 標記過已使用的券不再給「檢視加碼券」——按了也只是再走一次 OTP
                    // 看一張自己已經用掉的條碼。
                    if period.state == .redeemed && !isVoucherUsed {
                        Button {
                            onVoucherTap()
                        } label: {
                            Text("檢視加碼券")
                        }
                        .buttonStyle(.huihanPrimary)
                    }
                }
            }
        case .notStarted, .unknown:
            EmptyView()
        }
    }
}

// MARK: - Preview

/// 上傳鈕的兩種樣子並排。**這個預覽是有目的的**：`TaskPeriodCard.now` 一直寫著
/// 「預覽與測試可注入固定時間」，但在這之前沒有任何地方注入過它——而「已過期卻仍
/// `.open`」正是示範資料（`MockTasksService.sample(now:)` 的 14 期）與 UI 測試都做不出來的
/// 那張卡片。這裡用一個固定的 `now` 把它畫出來，至少讓排版與文案有地方可以肉眼回歸。
///
/// 判斷本身不靠這個預覽把關——它在 `TaskPeriod.canUpload(now:)`，由 `UploadWindowTests` 守著。
#Preview("可上傳 vs 已關窗") {
    // 台北時間 2026/09/07 09:00：9/1~9/6 那期已關窗，9/7~9/13 那期正開著。
    let now = TaskPeriod.activityCalendar.date(
        from: DateComponents(year: 2026, month: 9, day: 7, hour: 9)
    )!

    return ScrollView {
        VStack(spacing: 16) {
            TaskPeriodCard(
                period: TaskPeriod(id: "preview-open", index: 2,
                                   startDate: "2026/09/07", endDate: "2026/09/13",
                                   state: .open, remainingText: "剩 6 天 15 小時可上傳"),
                isHighlighted: true, isVoucherUsed: false,
                onRedeemTap: {}, onScreenshotTap: {}, onVoucherTap: {}, onUploadTap: {},
                now: now
            )
            // 官網對這張卡片照樣回 `NOT_UPLOADED` 與倒數字串——刻意兩個都給，
            // 預覽才反映得出真實資料的樣子（倒數會被 `showsRemaining` 擋掉）。
            TaskPeriodCard(
                period: TaskPeriod(id: "preview-closed", index: 1,
                                   startDate: "2026/09/01", endDate: "2026/09/06",
                                   state: .open, remainingText: "剩 3 小時可上傳"),
                isHighlighted: true, isVoucherUsed: false,
                onRedeemTap: {}, onScreenshotTap: {}, onVoucherTap: {}, onUploadTap: {},
                now: now
            )
        }
        .padding(20)
    }
    .background(Theme.Colors.background)
}

// MARK: - ViewModel

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var periods: [TaskPeriod] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// 這一次抓取是否撞上「官網結構對不上」（`SiteHandoff.shouldHandoff(_:)`）。
    /// 與 `errorMessage` 互斥：走接手畫面的錯誤不再套「請確認網路連線」那句。
    @Published private(set) var isSiteHandoff = false
    /// 使用者關掉了頂端 banner。**下一次抓取再失敗時要重新出現**，所以每次 `refresh` 開頭歸零。
    @Published var isSiteHandoffBannerDismissed = false

    /// 有快取可顯示、又撞上改版、而且使用者還沒關掉——三個條件都成立才掛 banner。
    var showsSiteHandoffBanner: Bool {
        isSiteHandoff && !periods.isEmpty && !isSiteHandoffBannerDismissed
    }

    private var tasks: TasksServicing?

    func configure(tasks: TasksServicing) {
        guard self.tasks == nil else { return }
        self.tasks = tasks
    }

    /// 本週要置頂高亮的那一期 index（第一個非 notStarted，找不到就用最新一期）。
    /// 用 index 而非 id：非當期的卡片後端沒有 UUID，id 會是空字串而彼此相同。
    var highlightedPeriodIndex: Int? {
        HomeViewModel.highlightedPeriod(in: periods)?.index
    }

    /// 本地優先：先秀快取；距上次更新未滿 60 秒則不再發 request。
    /// - Parameter force: 忽略節流。**使用者主動觸發的刷新（下拉、重試鈕、上傳後）一律傳
    ///   true**；預設的 false 只給畫面出現時的自動抓取用。
    ///
    ///   節流的時鐘是 `TasksCache` 的單一時戳，`HomeView` 與本頁共用它但各存各的資料——
    ///   所以首頁刷新過就會把這裡的 60 秒重新計時。這是為什麼「等超過 60 秒再下拉」
    ///   對使用者不是可靠的自救方式。
    func refresh(force: Bool = false) async {
        guard let tasks else { return }
        // 1. 先顯示快取（若目前空）
        if periods.isEmpty, let cached = TasksCache.load() {
            periods = Self.sorted(cached)
        }
        // 2. 節流：未滿間隔且已有資料就不發請求
        guard force || TasksCache.canRefresh() || periods.isEmpty else { return }

        let hadCache = !periods.isEmpty
        isLoading = periods.isEmpty
        errorMessage = nil
        // 每次抓取都是一次新的判斷：上次的接手狀態與「使用者關掉了 banner」一起歸零，
        // 這次再失敗 banner 才會重新出現。
        isSiteHandoff = false
        isSiteHandoffBannerDismissed = false
        defer { isLoading = false }
        let startedAt = DispatchTime.now()
        do {
            let fetched = try await tasks.fetchTasks()
            periods = Self.sorted(fetched)
            TasksCache.save(fetched)
            TasksTelemetry.reportSuccess(source: .tasksTab, periods: fetched,
                                         highlighted: HomeViewModel.highlightedPeriod(in: fetched),
                                         hadCache: hadCache, startedAt: startedAt)
        } catch {
            // 分頁本身可能是冷啟動後第一個被打開的畫面，解析失敗同樣可能只是 session 過期，
            // 因此這裡也走 sessionProbable，不把它當成官網改版警報。
            TasksTelemetry.reportFailure(error, source: .tasksTab, hadCache: hadCache,
                                         startedAt: startedAt, sessionProbable: true)
            // 官網結構對不上：有快取就照舊顯示、掛 banner；沒快取就走接手畫面。
            // 兩種情況都不套「請確認網路連線」——那句在這個情境下是錯誤歸因。
            if SiteHandoff.shouldHandoff(error) {
                isSiteHandoff = true
            } else if periods.isEmpty {
                // 其他錯誤：有快取就靜默沿用；完全沒資料才顯示錯誤。
                errorMessage = "無法載入任務資料，請確認網路連線後重新整理"
            }
        }
    }

    private static func sorted(_ periods: [TaskPeriod]) -> [TaskPeriod] {
        guard let highlighted = HomeViewModel.highlightedPeriod(in: periods) else {
            return periods.sorted(by: { $0.index < $1.index })
        }
        // 用 index 過濾，不能用 id：非當期（NOT_STARTED / NOT_UPLOADED）後端沒有 UUID，
        // id 皆為空字串，用 id 比對會把所有空 id 的期別一起濾掉，導致只剩高亮那一張。
        var rest = periods.filter { $0.index != highlighted.index }
        rest.sort(by: { $0.index < $1.index })
        return [highlighted] + rest
    }
}

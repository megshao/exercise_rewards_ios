import SwiftUI
import ExerciseRewardsKit

/// 首頁：一鍵登入 CTA、本週任務摘要卡、加碼券清單（最多五列）。
struct HomeView: View {
    @Environment(\.appEnvironment) private var environment
    @EnvironmentObject private var envStore: AppEnvironmentStore
    /// 「已使用」標記的共用真相來源。三個分頁同時活著，各自快照會不同步（見 `VoucherUsageStore`）。
    @EnvironmentObject private var voucherUsage: VoucherUsageStore
    @StateObject private var viewModel = HomeViewModel()
    @State private var showProfile = false
    @State private var redeemPeriod: TaskPeriod?
    @State private var voucherPeriod: TaskPeriod?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                loginCTA
                weeklyTaskSection
                voucherSection
            }
            .padding(20)
        }
        .background(Theme.Colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showProfile) {
            ProfileView()
        }
        .onAppear { Telemetry.screenAppeared(.home) }
        .task {
            viewModel.configure(auth: environment.auth, tasks: environment.tasks,
                                 profileStore: environment.profileStore, envStore: envStore)
            await viewModel.bootstrap()
        }
        .refreshable {
            viewModel.refreshProfileState()
            // 下拉是明確意圖，忽略節流（理由同 TasksView 的 refreshable）。
            await viewModel.loadWeeklySummary(force: true)
        }
        // 兌換完官網會把該期改成 REDEEMED，不重抓的話這一列會停在「尚未兌換」。
        .sheet(item: $redeemPeriod, onDismiss: {
            Task { await viewModel.loadWeeklySummary(force: true) }
        }) { period in
            NavigationStack { RedeemView(taskID: period.id, periodIndex: period.index) }
                .environment(\.appEnvironment, environment)
                // RedeemView 兌換成功後會再開 VoucherView，那一頁要 voucherUsage。
                .environmentObject(voucherUsage)
        }
        // 不需要 onDismiss 重讀標記：`voucherUsage` 是共用的 `@Published`，
        // 在券碼頁寫入的當下這一頁就已經重畫了。
        .sheet(item: $voucherPeriod) { period in
            NavigationStack { VoucherView(taskID: period.id, source: .wallet, periodIndex: period.index) }
                .environment(\.appEnvironment, environment)
                .environmentObject(voucherUsage)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.greeting)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.muted)
                (Text("揮汗").foregroundColor(Theme.Colors.text) + Text("有禮").foregroundColor(Theme.Colors.primary))
                    .font(Theme.displayFont(24, weight: .heavy))
            }
            Spacer()
            Button {
                showProfile = true
            } label: {
                Image(systemName: "person.fill")
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.card)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.Colors.line2, lineWidth: 1))
            }
            .accessibilityLabel("我的資料")
        }
    }

    /// 登入狀態列。整塊靠左對齊，與首頁其他區塊（問候語、本週任務、加碼券）同一條左邊界；
    /// 只有全寬按鈕本來就滿版，不受影響。
    @ViewBuilder
    private var loginCTA: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !viewModel.isProfileComplete {
                // 個資未填齊：引導去填寫，不顯示登入按鈕。
                NavigationLink {
                    ProfileView()
                } label: {
                    HStack {
                        Image(systemName: "person.text.rectangle")
                        Text("前往「我的資料」填寫個資")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if viewModel.isLoggingIn {
                // 自動登入中：顯示載入狀態，不需按鈕。
                HStack(spacing: 8) {
                    ProgressView()
                    Text("登入中…").foregroundStyle(Theme.Colors.muted)
                }
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else if viewModel.hasLoggedIn {
                // 已自動登入：不顯示登入按鈕。
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.Colors.success)
                    Text("已登入，任務資料已同步")
                        .foregroundStyle(Theme.Colors.muted)
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if viewModel.loginResultIsError {
                // 自動登入失敗：提供手動重試。
                Button {
                    Task { await viewModel.loginTapped() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("重新登入")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(isLoading: viewModel.isLoggingIn))
            }

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(Theme.Colors.dim)
                // 這行是首頁的信任徽章。加了 Firebase 之後，「不會上傳雲端」單獨看會被讀成
                // 「這支 App 什麼都不上傳」，所以改成把範圍講明白：講的是個資，去的是官方站。
                // 使用統計那條界線在「我的資料」的隱私聲明裡完整交代。
                Text("個資只存這支手機 · 只在登入時送給 500.gov.tw")
                    .foregroundStyle(Theme.Colors.dim)
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)

            if let message = viewModel.loginResultMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(viewModel.loginResultIsError ? Theme.Colors.danger : Theme.Colors.success)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private var weeklyTaskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本週任務")
                    .font(Theme.displayFont(16, weight: .bold))
                Spacer()
                NavigationLink {
                    TasksView()
                } label: {
                    Text("全部 14 期 ›")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.primary)
                }
            }

            if viewModel.isLoadingSummary {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if let task = viewModel.currentWeekTask {
                TaskSummaryCard(task: task)
            } else {
                Text("目前沒有任務資料，下拉重新整理試試。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
    }

    /// 加碼券區塊：把「可兌換」與「已兌換」兩種期別合成同一份清單。
    ///
    /// 排序與截斷的規則都在 `HomeViewModel.sortedVoucherRows`／`voucherRows(usedIDs:)`，
    /// 這裡只負責畫。超過五列時顯示「查看全部」導向券夾，避免首頁被 14 期塞滿。
    private var voucherSection: some View {
        let all = viewModel.allVoucherRows(usedIDs: voucherUsage.usedIDs)
        let rows = Array(all.prefix(HomeViewModel.voucherRowLimit))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("加碼券")
                    .font(Theme.displayFont(16, weight: .bold))
                Spacer()
                if all.count > HomeViewModel.voucherRowLimit {
                    NavigationLink {
                        WalletView()
                    } label: {
                        Text("查看全部 \(all.count) 張 ›")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Colors.primary)
                    }
                }
            }

            if viewModel.isLoadingSummary {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if rows.isEmpty {
                Text("目前沒有加碼券。完成任務並兌換後，加碼券會出現在這裡。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.muted)
            } else {
                VStack(spacing: 10) {
                    ForEach(rows, id: \.index) { period in
                        VoucherRowCard(
                            period: period,
                            isUsed: voucherUsage.isUsed(period),
                            onRedeemTap: { redeemPeriod = period },
                            onVoucherTap: { voucherPeriod = period }
                        )
                    }
                }
            }
        }
    }
}

/// 首頁的加碼券單列：一列一期，左側期別／兌換內容，右側動作鈕。
///
/// - 尚未兌換 → 「去兌換」開 RedeemView（二次確認在該頁）。
/// - 已兌換 → 「顯示條碼」開 VoucherView（每次都要重走一次簡訊 OTP）。
/// - 已兌換且**使用者自己標記過已使用** → 整列轉灰、標「已使用」、**不放任何按鈕**。
///   官網沒有這個狀態（見 `VoucherUsage` 的說明），所以只能靠使用者告訴 App；
///   要還原請到券夾或券碼頁。
private struct VoucherRowCard: View {
    let period: TaskPeriod
    let isUsed: Bool
    let onRedeemTap: () -> Void
    let onVoucherTap: () -> Void

    private var isRedeemed: Bool { period.state == .redeemed }

    var body: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("第 \(period.index) 期加碼券")
                        .font(Theme.displayFont(14.5, weight: .bold))
                        .foregroundStyle(isUsed ? Theme.Colors.muted : Theme.Colors.text)
                    if isUsed {
                        StatusBadge(text: "已使用",
                                    foreground: Theme.Colors.dim,
                                    background: Color(hex: 0xEEF0F3))
                    }
                }
                // 官網卡片上的「兌換內容：通路／品項」。是官網原文，只顯示、不進遙測。
                if let summary = period.voucherSummary {
                    Text(summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Colors.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(statusText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: 8)

            action
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isUsed ? Color(hex: 0xFAFBFC) : Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(Theme.Colors.line, lineWidth: 1)
        )
    }

    private var icon: some View {
        let name = isUsed ? "checkmark" : (isRedeemed ? "ticket.fill" : "gift.fill")
        let tint: Color = isUsed ? Theme.Colors.dim : (isRedeemed ? Theme.Colors.primary : Theme.Colors.success)
        let background: Color = isUsed ? Color(hex: 0xEEF0F3)
            : (isRedeemed ? Theme.Colors.card2 : Theme.Colors.successBackground)
        return Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var statusText: String {
        if isUsed { return "已使用 · 本機紀錄，以條碼能否使用為主" }
        return isRedeemed ? "已兌換 · 可出示條碼使用" : "任務完成 · 尚未兌換"
    }

    private var statusColor: Color {
        if isUsed { return Theme.Colors.dim }
        return isRedeemed ? Theme.Colors.muted : Theme.Colors.success
    }

    /// 已標記使用的列**不放任何按鈕**：首頁只負責讓人一眼看出「哪幾張還沒用」。
    /// 標記錯了要改回來是修正動作，入口留在券夾與券碼頁就夠了——在首頁多一顆「還原」
    /// 會讓同一區同時出現「去用它」與「我標錯了」兩種語意的按鈕。
    @ViewBuilder
    private var action: some View {
        if !isUsed {
            Button(action: isRedeemed ? onVoucherTap : onRedeemTap) {
                Text(isRedeemed ? "顯示條碼" : "去兌換")
                    .font(Theme.displayFont(12.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(isRedeemed ? Theme.Colors.primary : Theme.Colors.success)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// 首頁用的本週任務摘要卡（精簡版，完整卡片見 TasksView）。
private struct TaskSummaryCard: View {
    let task: TaskPeriod
    /// 判斷「這一期是否已經過完」的基準時間。預設當下，預覽與測試可注入固定時間。
    var now: Date = Date()

    private var hasEnded: Bool { task.hasEnded(now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Text("第 \(task.index) 期")
                        .font(Theme.displayFont(15, weight: .bold))
                    Text("\(task.startDate) ~ \(task.endDate)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.muted)
                }
                Spacer()
                TaskStateBadge(state: task.state, hasEnded: hasEnded)
            }

            // 進度時間軸：上傳 → 審核 → 兌換（依狀態上色）。取代舊的百分比條，
            // 已審核/已兌換等完成狀態不再顯示剩餘時間條。
            TaskStepper(state: task.state)

            statusLine
        }
        .cardStyle()
    }

    @ViewBuilder
    private var statusLine: some View {
        switch task.state {
        case .open:
            // 與任務頁的上傳鈕走同一條規則（`TaskPeriod.canUpload(now:)`，由
            // `UploadWindowTests` 守著），兩頁不會再各自寫一次「.open 且未過期」的合取。
            if !task.canUpload(now: now) {
                // 官網對過期未上傳的卡片仍會回倒數字串，照著顯示等於告訴使用者「還有時間」。
                Text("本期已結束，未上傳運動紀錄")
                    .font(.system(size: 12)).foregroundStyle(Theme.Colors.dim)
            } else if let t = task.remainingText, let h = RemainingTime.hours(from: t) {
                Text(t)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RemainingTime.color(forHours: h))
            } else {
                Text("尚未上傳，請於上傳期間內送出運動紀錄")
                    .font(.system(size: 12)).foregroundStyle(Theme.Colors.muted)
            }
        case .pendingReview:
            Text("審核中 · 約 5 個工作日")
                .font(.system(size: 12)).foregroundStyle(Theme.Colors.muted)
        case .redeemable:
            Text("任務完成，可兌換超商加碼券")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Colors.success)
        case .redeemed:
            Text("已兌換 · 券已存入券夾")
                .font(.system(size: 12)).foregroundStyle(Theme.Colors.muted)
        case .notStarted, .unknown:
            if task.state.showsUploadCountdown, let t = task.remainingText {
                Text(t).font(.system(size: 12)).foregroundStyle(Theme.Colors.muted)
            }
        }
    }
}

/// 三段式進度時間軸：上傳 → 審核 → 兌換。節點依狀態顯示 完成(綠勾) / 進行中(填色圖示) /
/// 未開始(灰框)；連接線在該段完成時轉綠。對齊設計稿。
private struct TaskStepper: View {
    let state: TaskState

    private enum Node { case done, active, pending }

    /// 狀態排序：未開始0 未上傳1 審核中2 可兌換3 已兌換4。
    private var order: Int {
        switch state {
        case .notStarted, .unknown: return 0
        case .open: return 1
        case .pendingReview: return 2
        case .redeemable: return 3
        case .redeemed: return 4
        }
    }
    private func node(step: Int) -> Node {
        if order > step { return .done }
        if order == step { return .active }
        return .pending
    }

    var body: some View {
        HStack(spacing: 6) {
            stepView(step: 1, label: "上傳", icon: "arrow.up", activeColor: Theme.Colors.primary)
            connector(green: order >= 2)
            stepView(step: 2, label: "審核", icon: "magnifyingglass", activeColor: Color(hex: 0xE6A100))
            connector(green: order >= 3)
            stepView(step: 3, label: "兌換", icon: "gift.fill", activeColor: Theme.Colors.success)
        }
    }

    private func connector(green: Bool) -> some View {
        Capsule()
            .fill(green ? Theme.Colors.success : Color(hex: 0xE0E3E9))
            .frame(height: 3)
            .frame(maxWidth: .infinity)
            .offset(y: -9) // 對齊節點圓心（節點下方有文字）
    }

    private func stepView(step: Int, label: String, icon: String, activeColor: Color) -> some View {
        let n = node(step: step)
        let circleColor: Color = n == .done ? Theme.Colors.success
            : n == .active ? activeColor : .white
        let iconName = n == .done ? "checkmark" : icon
        let iconColor: Color = n == .pending ? Theme.Colors.dim : .white
        return VStack(spacing: 4) {
            ZStack {
                Circle().fill(circleColor)
                if n == .pending {
                    Circle().stroke(Color(hex: 0xE0E3E9), lineWidth: 2)
                }
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 24, height: 24)
            Text(label)
                .font(.system(size: 10, weight: n == .pending ? .regular : .semibold))
                .foregroundStyle(n == .pending ? Theme.Colors.dim : Theme.Colors.text)
        }
        .frame(width: 40)
    }
}

/// 解析後端的「剩 X 天 Y 小時」倒數字串，並依剩餘時間換算比例與顏色。
enum RemainingTime {
    /// 上傳窗總長：每期 7 天。比例以此為分母。
    static let windowHours: Double = 7 * 24

    /// 從「剩 1 天 22 小時」/「剩 22 小時」/「剩 1 天」解析出剩餘小時數；無法解析回 nil。
    static func hours(from text: String) -> Double? {
        var days = 0.0, hrs = 0.0, matched = false
        if let d = firstNumber(in: text, before: "天") { days = d; matched = true }
        if let h = firstNumber(in: text, before: "小時") { hrs = h; matched = true }
        guard matched else { return nil }
        return days * 24 + hrs
    }

    /// 填滿比例（0...1），越少越短；至少留一點點寬度以免完全消失。
    static func fraction(forHours h: Double) -> Double {
        min(1, max(0.02, h / windowHours))
    }

    /// 顏色：> 3 天綠、1–3 天橘、< 1 天紅。
    static func color(forHours h: Double) -> Color {
        if h >= 72 { return Theme.Colors.success }
        if h >= 24 { return Theme.Colors.primary }
        return Theme.Colors.danger
    }

    private static func firstNumber(in text: String, before unit: String) -> Double? {
        guard let unitRange = text.range(of: unit) else { return nil }
        // 取 unit 前面連續的數字
        let prefix = text[text.startIndex..<unitRange.lowerBound]
        var digits = ""
        for ch in prefix.reversed() {
            if ch.isNumber { digits.insert(ch, at: digits.startIndex) }
            else if ch == " " { continue }
            else if !digits.isEmpty { break }
        }
        return digits.isEmpty ? nil : Double(digits)
    }
}

// MARK: - TaskState UI helpers (shared with TasksView)

extension TaskState {
    // `showsUploadCountdown` 定義在 ExerciseRewardsKit 的 `TaskState` 上：
    // 那是「官網這個欄位在這個狀態下還有沒有意義」的判斷，屬領域規則而非排版，
    // 放在 Kit 才有單元測試守得住（見 `TaskStateTests`）。

    var badgeText: String {
        switch self {
        case .notStarted: return "尚未開始"
        case .open: return "未上傳"
        case .pendingReview: return "審核中"
        case .redeemable: return "可兌換"
        case .redeemed: return "已兌換"
        case .unknown: return "—"
        }
    }

    var badgeForeground: Color {
        switch self {
        case .notStarted, .redeemed, .unknown: return Theme.Colors.dim
        case .open: return Theme.Colors.primaryDark
        case .pendingReview: return Theme.Colors.warnText
        case .redeemable: return .white
        }
    }

    var badgeBackground: Color {
        switch self {
        case .notStarted, .unknown: return Theme.Colors.disabledBackground
        case .redeemed: return Color(hex: 0xEEF0F3)
        case .open: return Color(hex: 0xFFECE1)
        case .pendingReview: return Theme.Colors.warnBackground
        case .redeemable: return Theme.Colors.success
        }
    }

}

struct TaskStateBadge: View {
    let state: TaskState
    /// 上傳窗已經過完的期別。官網對這種卡片照樣回 `NOT_UPLOADED`（→ `.open`），
    /// 直接顯示「未上傳」會讓使用者以為還來得及補傳，所以這裡換成「已結束」。
    /// 預設 false，讓不需要判斷日期的呼叫端維持原樣。
    var hasEnded: Bool = false

    var body: some View {
        if state == .open, hasEnded {
            StatusBadge(text: "已結束",
                        foreground: Theme.Colors.dim,
                        background: Theme.Colors.disabledBackground)
        } else {
            StatusBadge(text: state.badgeText, foreground: state.badgeForeground, background: state.badgeBackground)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var isLoggingIn = false
    @Published var loginResultMessage: String?
    @Published var loginResultIsError = false
    @Published var hasLoggedIn = false
    @Published var isProfileComplete = false
    private var didAutoLogin = false

    @Published var isLoadingSummary = false

    /// 首頁的加碼券區塊要跨期別排序，因此保留整份清單而非只留高亮那一期。
    @Published var periods: [TaskPeriod] = []


    /// 本週要高亮的那一期（第一個非 notStarted，找不到就用最新一期）。
    var currentWeekTask: TaskPeriod? { Self.highlightedPeriod(in: periods) }

    /// 首頁加碼券清單最多顯示幾列。超過的部分請使用者去券夾看完整清單。
    static let voucherRowLimit = 5

    /// 排序後但**未截斷**的完整清單。呼叫端自己 `prefix(voucherRowLimit)`，
    /// 未截斷的長度用來判斷要不要顯示「查看全部」入口。
    func allVoucherRows(usedIDs: Set<String>) -> [TaskPeriod] {
        Self.sortedVoucherRows(in: periods, usedIDs: usedIDs)
    }

    /// 可兌換（尚未兌換）與已兌換的期別，依三段優先序排序：
    ///
    /// 1. **尚未兌換**（`REDEEMABLE`）——還要動手才拿得到券，最該先看到
    /// 2. **已兌換、還沒用掉**（`REDEEMED` 且未標記）——手上真正能用的券
    /// 3. **已標記使用完畢**——只是留著給使用者對帳，排最後
    ///
    /// 同一段內再依建立時間由舊到新。期別 index 就是建立順序（第 1 期最早、第 14 期最晚），
    /// 所以用 index 遞增即可，不需要解析 `startDate` 字串。
    ///
    /// **為什麼「已使用」要排最後**：首頁只有五列。用過的券如果照原順序卡在前面，
    /// 就會把還沒用的券擠出畫面——而那正是使用者打開 App 想找的東西。
    static func sortedVoucherRows(in periods: [TaskPeriod], usedIDs: Set<String>) -> [TaskPeriod] {
        /// 0 = 尚未兌換、1 = 已兌換未使用、2 = 已標記使用。
        func rank(_ period: TaskPeriod) -> Int {
            if period.state == .redeemable { return 0 }
            return usedIDs.contains(period.id) ? 2 : 1
        }

        return periods
            .filter { $0.state == .redeemable || $0.state == .redeemed }
            // 非當期的卡片後端沒有 UUID，點進兌換／券碼頁都會失敗，因此不列出來。
            .filter { !$0.id.isEmpty }
            .sorted { lhs, rhs in
                let lhsRank = rank(lhs)
                let rhsRank = rank(rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.index < rhs.index
            }
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早安，動起來！"
        case 12..<18: return "午安，動起來！"
        default: return "晚安，今天運動了嗎？"
        }
    }

    private var auth: AuthServicing?
    private var tasks: TasksServicing?
    private var profileStore: ProfileStoring?
    private weak var envStore: AppEnvironmentStore?

    func configure(auth: AuthServicing, tasks: TasksServicing, profileStore: ProfileStoring,
                   envStore: AppEnvironmentStore) {
        guard self.auth == nil else { return }
        self.auth = auth
        self.tasks = tasks
        self.profileStore = profileStore
        self.envStore = envStore
    }

    /// 本地優先 + 節流：先秀快取；距上次更新未滿 60 秒（且已有資料）就不發 request。
    ///
    /// `force == true` 只發生在「剛登入成功」之後，因此遙測來源標成 `post_login`——
    /// 這是用來分辨「官網改版」與「session 過期」的關鍵：
    /// 剛登入完還解析失敗，就不可能是 session 過期了。
    func loadWeeklySummary(force: Bool = false) async {
        guard let tasks else { return }
        if periods.isEmpty, let cached = TasksCache.load() {
            periods = cached
        }
        guard force || TasksCache.canRefresh() || periods.isEmpty else { return }
        let hadCache = !periods.isEmpty
        isLoadingSummary = periods.isEmpty
        defer { isLoadingSummary = false }
        let startedAt = DispatchTime.now()
        do {
            let fetched = try await tasks.fetchTasks()
            periods = fetched
            TasksCache.save(fetched)
            TasksTelemetry.reportSuccess(
                source: force ? .postLogin : .homeRefresh,
                periods: fetched,
                highlighted: currentWeekTask,
                hadCache: hadCache,
                startedAt: startedAt
            )
        } catch {
            TasksTelemetry.reportFailure(
                error,
                source: force ? .postLogin : .homeRefresh,
                hadCache: hadCache,
                startedAt: startedAt,
                // post_login 的解析失敗才是改版訊號；一般刷新可能只是 session 剛過期。
                sessionProbable: !force
            )
            // 有快取就沿用，不清掉。
        }
    }

    /// 挑出「本週」要高亮的那一期。規則與踩過的坑都在 `TaskPeriod.current(in:now:)`
    /// ——那是領域規則不是排版，放在 Kit 才有單元測試守得住（見 `PeriodSelectionTests`）。
    ///
    /// - Parameter now: 判斷基準時間。預設當下；測試與預覽可注入固定時間。
    static func highlightedPeriod(in periods: [TaskPeriod], now: Date = Date()) -> TaskPeriod? {
        TaskPeriod.current(in: periods, now: now)
    }

    /// 進入 App 時的啟動流程（只做一次）：
    /// 1. 先**沿用持久化 session** 試抓任務——若成功代表上次登入的 cookie 還有效，直接免登入。
    /// 2. 只有在 session 失效（抓不到任務）時，才用 Keychain 個資自動登入。
    /// 這樣一般冷啟動不會每次都重新登入。
    func bootstrap() async {
        refreshProfileState()
        // 本地優先：先秀快取的本週任務（有快取代表先前登入過，樂觀視為已登入）。
        var hadCache = false
        if let cached = TasksCache.load() {
            periods = cached
            hasLoggedIn = true
            hadCache = true
        }
        Telemetry.setCrashKey(.tasksCache(hadCache ? (TasksCache.canRefresh() ? .stale : .fresh) : .none))
        Telemetry.setCrashKey(.sessionState(isProfileComplete ? (hadCache ? .cachedOnly : .loggedIn)
                                                             : .profileMissing))
        if isProfileComplete && !didAutoLogin {
            didAutoLogin = true
            // 節流：距上次更新未滿 60 秒且已有快取，就不發請求。
            if TasksCache.canRefresh() || periods.isEmpty {
                let startedAt = DispatchTime.now()
                do {
                    let fetched = try await tasks?.fetchTasks() ?? []
                    guard !fetched.isEmpty else { throw AppError.parsing("empty task list") }
                    hasLoggedIn = true
                    periods = fetched
                    TasksCache.save(fetched)
                    TasksTelemetry.reportSuccess(source: .homeBootstrap, periods: fetched,
                                                 highlighted: currentWeekTask, hadCache: hadCache,
                                                 startedAt: startedAt)
                } catch {
                    // 冷啟動的第一次抓取失敗**幾乎都是 session 過期**（官網 302 到登入頁，
                    // 回的是登入頁 HTML，解析器丟出的錯誤跟官網改版一模一樣）。
                    // 因此這裡歸類為 `session_probable`，不送 Crashlytics 非致命錯誤——
                    // 不然每個使用者每天冷啟動都會產生一筆假的「官網改版」警報。
                    TasksTelemetry.reportFailure(error, source: .homeBootstrap, hadCache: hadCache,
                                                 startedAt: startedAt, sessionProbable: true)
                    await performLogin(silent: true)  // 內部成功會強制抓一次最新
                }
            }
        }
    }

    /// 使用者手動點「重新登入」時呼叫。
    func loginTapped() async {
        await performLogin(silent: false)
    }

    /// 依 Keychain 個資判斷登入必要欄位是否齊全。
    func refreshProfileState() {
        let profile = try? profileStore?.load()
        if let p = profile ?? nil {
            isProfileComplete = !p.idNo.isEmpty && !p.birthDate.isEmpty && !p.phone.isEmpty
        } else {
            isProfileComplete = false
        }
    }

    /// 執行登入。silent = 自動登入（成功不顯示提示，只在失敗時提示）。
    private func performLogin(silent: Bool) async {
        guard let auth, let profileStore else { return }
        isLoggingIn = true
        loginResultMessage = nil
        defer { isLoggingIn = false }
        let trigger: LoginTrigger = silent ? .auto : .manual
        let startedAt = DispatchTime.now()

        do {
            guard let profile = try profileStore.load(),
                  !profile.idNo.isEmpty, !profile.birthDate.isEmpty, !profile.phone.isEmpty else {
                isProfileComplete = false
                loginResultIsError = true
                loginResultMessage = "請先到「我的資料」填寫身分證號、出生日期與手機號碼"
                return
            }

            let credentials = LoginCredentials(idNo: profile.idNo, birthDate: profile.birthDate, phone: profile.phone)

            // 示範帳號（App Store 審查用）：不連線，改用示範環境的任務資料。已在示範模式時
            // environment 本來就是 Mock，這裡只處理「從真實環境輸入示範帳號」的情況。
            if let envStore, envStore.enterDemoIfSentinel(credentials) {
                hasLoggedIn = true
                loginResultIsError = false
                loginResultMessage = silent ? nil : "示範模式已啟用，顯示的是範例資料"
                if let fetched = try? await envStore.environment.tasks.fetchTasks() {
                    periods = fetched
                }
                return
            }

            let outcome = try await auth.login(credentials)
            let elapsed = Telemetry.elapsedMs(since: startedAt)

            switch outcome {
            case .success:
                hasLoggedIn = true
                loginResultIsError = false
                loginResultMessage = silent ? nil : "登入成功，正在載入我的任務"
                Telemetry.setCrashKey(.sessionState(.loggedIn))
                // E4
                Telemetry.logEvent(.login(trigger: trigger, durationMs: elapsed))
                await loadWeeklySummary(force: true)  // 剛登入，強制抓一次最新並寫入快取
            case .notRegistered:
                loginResultIsError = true
                loginResultMessage = "這組身分證號尚未在「揮汗有禮」官網註冊，請先至官網完成註冊"
                Telemetry.setCrashKey(.sessionState(.loginFailed))
                Telemetry.logEvent(.loginFailed(trigger: trigger, reason: .notRegistered,
                                                netCode: nil, durationMs: elapsed))
            case .invalidCredentials:
                loginResultIsError = true
                loginResultMessage = "身分證號、出生日期或手機號碼有誤，請至「我的資料」確認後再試一次"
                Telemetry.setCrashKey(.sessionState(.loginFailed))
                Telemetry.logEvent(.loginFailed(trigger: trigger, reason: .invalidCredentials,
                                                netCode: nil, durationMs: elapsed))
            }
        } catch {
            loginResultIsError = true
            loginResultMessage = Self.message(for: error)
            Telemetry.setCrashKey(.sessionState(.loginFailed))
            let reason = Telemetry.reportFailure(error, endpoint: .login)
            Telemetry.logEvent(.loginFailed(trigger: trigger, reason: reason,
                                            netCode: Telemetry.networkCode(from: error),
                                            durationMs: Telemetry.elapsedMs(since: startedAt)))
        }
    }

    private static func message(for error: Error) -> String {
        if let appError = error as? AppError {
            switch appError {
            case .network: return "網路連線異常，請檢查網路後再試一次"
            case .csrfNotFound, .unexpectedResponse, .parsing, .responseTooLarge:
                return "官網回應異常，請稍後再試"
            case .notLoggedIn: return "尚未登入，請先完成一鍵登入"
            case .blockedEgress: return "偵測到非官方網域連線，已阻擋"
            }
        }
        return "發生未知錯誤，請稍後再試一次"
    }
}

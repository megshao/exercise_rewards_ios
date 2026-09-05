import SwiftUI
import SportsRewardsKit

/// 首頁：一鍵登入 CTA、今日步數圓環占位、本週任務摘要卡。
/// 對齊 design/Main.dc.html。
struct HomeView: View {
    @Environment(\.appEnvironment) private var environment
    @EnvironmentObject private var sensitiveAuth: SensitiveAuthCoordinator
    @StateObject private var viewModel = HomeViewModel()
    @State private var showProfile = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                stepsRingCard
                loginCTA
                weeklyTaskSection
            }
            .padding(20)
        }
        .background(Theme.Colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showProfile) {
            ProfileView()
        }
        .task {
            viewModel.configure(auth: environment.auth, tasks: environment.tasks,
                                 profileStore: environment.profileStore, health: environment.health)
            await viewModel.bootstrap()
        }
        .refreshable {
            viewModel.refreshProfileState()
            await viewModel.loadWeeklySummary()
            await viewModel.loadHealthSummary()
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
                // 敏感動作再驗證：進入個資設定頁前先過 Face ID（或 fallback）。
                Task {
                    if await sensitiveAuth.authorize(reason: "驗證身份以查看個資") {
                        showProfile = true
                    }
                }
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

    private var stepsRingCard: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(Color(hex: 0xECEEF2), lineWidth: 13)
                Circle()
                    .trim(from: 0, to: viewModel.stepsProgress)
                    .stroke(Theme.Colors.ringGradient, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(viewModel.todaySteps)")
                        .font(Theme.displayFont(30, weight: .heavy))
                    Text("今日步數")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 12) {
                if viewModel.hasReachedGoal {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text("已達今日目標")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Theme.Colors.success)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Theme.Colors.successBackground)
                    .clipShape(Capsule())
                }
                Text("目標 \(viewModel.goalSteps) 步\n距離 \(viewModel.distanceText) · 運動 \(viewModel.activeMinutes) 分")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.muted)
                if !viewModel.isHealthDataConnected {
                    Text("尚未連結 Apple 健康，前往「健康」分頁授權")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.dim)
                }
            }
        }
        // E. 卡片寬度一致：舊版沒有 Spacer/maxWidth，內容較短時會比本週任務卡窄，這裡強制滿版。
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private var loginCTA: some View {
        VStack(spacing: 9) {
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
                .frame(maxWidth: .infinity)
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
                Text("個資只存這支手機 · Face ID 保護")
                    .foregroundStyle(Theme.Colors.dim)
            }
            .font(.system(size: 12))

            if let message = viewModel.loginResultMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(viewModel.loginResultIsError ? Theme.Colors.danger : Theme.Colors.success)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
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
}

/// 首頁用的本週任務摘要卡（精簡版，完整卡片見 TasksView）。
private struct TaskSummaryCard: View {
    let task: TaskPeriod

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
                TaskStateBadge(state: task.state)
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
            if let t = task.remainingText, let h = RemainingTime.hours(from: t) {
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
            if let t = task.remainingText {
                Text(t).font(.system(size: 12)).foregroundStyle(Theme.Colors.muted)
            }
        }
    }
}

/// 三段式進度時間軸：上傳 → 審核 → 兌換。節點依狀態顯示 完成(綠勾) / 進行中(填色圖示) /
/// 未開始(灰框)；連接線在該段完成時轉綠。對齊 design/task-card 方向 D。
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

    var body: some View {
        StatusBadge(text: state.badgeText, foreground: state.badgeForeground, background: state.badgeBackground)
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
    @Published var currentWeekTask: TaskPeriod?

    // 今日健康摘要：已連結 Apple 健康時採真實資料，否則沿用示意占位值。
    @Published private(set) var healthSummary: HealthSummary?
    @Published private(set) var isHealthDataConnected = false

    let goalSteps = 8_000
    private static let placeholderSteps = 9_688
    private static let placeholderDistanceMeters = 6_400.0
    private static let placeholderActiveMinutes = 42

    var todaySteps: Int { healthSummary?.steps ?? Self.placeholderSteps }
    var activeMinutes: Int { healthSummary?.exerciseMinutes ?? Self.placeholderActiveMinutes }
    var distanceText: String {
        let km = (healthSummary?.distanceMeters ?? Self.placeholderDistanceMeters) / 1_000.0
        return String(format: "%.1f km", km)
    }
    var stepsProgress: Double { min(1.0, Double(todaySteps) / Double(goalSteps)) }
    var hasReachedGoal: Bool { todaySteps >= goalSteps }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早安，動起來！"
        case 12..<18: return "午安，動起來！"
        default: return "晚安，別忘了今天的步數！"
        }
    }

    private var auth: AuthServicing?
    private var tasks: TasksServicing?
    private var profileStore: ProfileStoring?
    private var health: HealthReading?

    func configure(auth: AuthServicing, tasks: TasksServicing, profileStore: ProfileStoring, health: HealthReading) {
        guard self.auth == nil else { return }
        self.auth = auth
        self.tasks = tasks
        self.profileStore = profileStore
        self.health = health
    }

    /// 讀取今日健康摘要（唯讀，需已授權）。未授權或讀取失敗時維持占位值，不視為錯誤。
    func loadHealthSummary() async {
        guard let health else { return }
        guard await health.isAuthorized() else {
            isHealthDataConnected = false
            healthSummary = nil
            return
        }
        do {
            healthSummary = try await health.summary(for: Date())
            isHealthDataConnected = true
        } catch {
            isHealthDataConnected = false
            healthSummary = nil
        }
    }

    /// 本地優先 + 節流：先秀快取；距上次更新未滿 60 秒（且已有資料）就不發 request。
    func loadWeeklySummary(force: Bool = false) async {
        guard let tasks else { return }
        if currentWeekTask == nil, let cached = TasksCache.load() {
            currentWeekTask = Self.highlightedPeriod(in: cached)
        }
        guard force || TasksCache.canRefresh() || currentWeekTask == nil else { return }
        isLoadingSummary = currentWeekTask == nil
        defer { isLoadingSummary = false }
        do {
            let periods = try await tasks.fetchTasks()
            currentWeekTask = Self.highlightedPeriod(in: periods)
            TasksCache.save(periods)
        } catch {
            // 有快取就沿用，不清掉。
        }
    }

    /// 挑出「本週」要高亮的那一期：第一個非 notStarted 的期別，找不到就用最新一期。
    static func highlightedPeriod(in periods: [TaskPeriod]) -> TaskPeriod? {
        periods.first(where: { $0.state != .notStarted }) ?? periods.max(by: { $0.index < $1.index })
    }

    /// 進入 App 時的啟動流程（只做一次）：
    /// 1. 先**沿用持久化 session** 試抓任務——若成功代表上次登入的 cookie 還有效，直接免登入。
    /// 2. 只有在 session 失效（抓不到任務）時，才用 Keychain 個資自動登入。
    /// 這樣一般冷啟動不會每次都重新登入。
    func bootstrap() async {
        refreshProfileState()
        // 本地優先：先秀快取的本週任務（有快取代表先前登入過，樂觀視為已登入）。
        if let cached = TasksCache.load() {
            currentWeekTask = Self.highlightedPeriod(in: cached)
            hasLoggedIn = true
        }
        if isProfileComplete && !didAutoLogin {
            didAutoLogin = true
            // 節流：距上次更新未滿 60 秒且已有快取，就不發請求。
            if TasksCache.canRefresh() || currentWeekTask == nil {
                if let periods = try? await tasks?.fetchTasks(), !periods.isEmpty {
                    hasLoggedIn = true
                    currentWeekTask = Self.highlightedPeriod(in: periods)
                    TasksCache.save(periods)
                } else {
                    await performLogin(silent: true)  // 內部成功會強制抓一次最新
                }
            }
        }
        await loadHealthSummary()
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

        do {
            guard let profile = try profileStore.load(),
                  !profile.idNo.isEmpty, !profile.birthDate.isEmpty, !profile.phone.isEmpty else {
                isProfileComplete = false
                loginResultIsError = true
                loginResultMessage = "請先到「我的資料」填寫身分證號、出生日期與手機號碼"
                return
            }

            let credentials = LoginCredentials(idNo: profile.idNo, birthDate: profile.birthDate, phone: profile.phone)
            let outcome = try await auth.login(credentials)

            switch outcome {
            case .success:
                hasLoggedIn = true
                loginResultIsError = false
                loginResultMessage = silent ? nil : "登入成功，正在載入我的任務"
                await loadWeeklySummary(force: true)  // 剛登入，強制抓一次最新並寫入快取
            case .notRegistered:
                loginResultIsError = true
                loginResultMessage = "這組身分證號尚未在「揮汗有禮」官網註冊，請先至官網完成註冊"
            case .invalidCredentials:
                loginResultIsError = true
                loginResultMessage = "身分證號、出生日期或手機號碼有誤，請至「我的資料」確認後再試一次"
            }
        } catch {
            loginResultIsError = true
            loginResultMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        if let appError = error as? AppError {
            switch appError {
            case .network: return "網路連線異常，請檢查網路後再試一次"
            case .csrfNotFound, .unexpectedResponse, .parsing: return "官網回應異常，請稍後再試"
            case .notLoggedIn: return "尚未登入，請先完成一鍵登入"
            case .blockedEgress: return "偵測到非官方網域連線，已阻擋"
            }
        }
        return "發生未知錯誤，請稍後再試一次"
    }
}

import SwiftUI
import SportsRewardsKit

/// 首頁：一鍵登入 CTA、今日步數圓環占位、本週任務摘要卡。
/// 對齊設計稿。
struct HomeView: View {
    @Environment(\.appEnvironment) private var environment
    @EnvironmentObject private var envStore: AppEnvironmentStore
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
        .onAppear { Telemetry.screenAppeared(.home) }
        .task {
            viewModel.configure(auth: environment.auth, tasks: environment.tasks,
                                 profileStore: environment.profileStore, health: environment.health,
                                 envStore: envStore)
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

    /// 今日步數卡：已連結 Apple 健康才顯示真實數字；未連結時整個環與圖案改為
    /// 淺灰半透明的「未連結」占位，不再顯示任何看起來像真實數據的數字。
    private var stepsRingCard: some View {
        HStack(spacing: 22) {
            switch viewModel.healthLink {
            case .linked:
                connectedRing
            case .checking, .notLinked:
                placeholderRing
            }

            VStack(alignment: .leading, spacing: 12) {
                switch viewModel.healthLink {
                case .linked:
                    connectedDetail
                case .checking:
                    Text("讀取健康資料中…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.muted)
                case .notLinked:
                    notLinkedDetail
                }
            }
        }
        // E. 卡片寬度一致：舊版沒有 Spacer/maxWidth，內容較短時會比本週任務卡窄，這裡強制滿版。
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var connectedRing: some View {
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
    }

    /// 未連結（或仍在確認授權）時的占位圖案：淺灰虛線環 + 灰色步行圖示，整體半透明，
    /// 一眼就看得出「這裡還沒有資料」而不是「今天走了 0 步」。
    private var placeholderRing: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: 0xD8DCE3),
                        style: StrokeStyle(lineWidth: 13, lineCap: .round, dash: [2, 10]))
            VStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 30, weight: .semibold))
                if viewModel.healthLink == .notLinked {
                    Text("未連結")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.Colors.dim)
        }
        .frame(width: 120, height: 120)
        .opacity(0.55)
        .accessibilityLabel(viewModel.healthLink == .notLinked ? "尚未連結 Apple 健康" : "讀取健康資料中")
    }

    private var connectedDetail: some View {
        Group {
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
        }
    }

    private var notLinkedDetail: some View {
        Group {
            Text("尚未連結 Apple 健康")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.Colors.text)
            Text("連結後才會顯示今日步數、距離與運動時間。\n健康數據只在本機顯示，不會被送出。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                HealthView()
            } label: {
                HStack(spacing: 4) {
                    Text("前往連結")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.primary)
            }
        }
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
                // 這行是首頁的信任徽章。加了 Firebase 之後，「不會上傳雲端」單獨看會被讀成
                // 「這支 App 什麼都不上傳」，所以改成把範圍講明白：講的是個資，去的是官方站。
                // 使用統計那條界線在「我的資料」的隱私聲明裡完整交代。
                Text("個資只存這支手機 · 只在登入時送給 500.gov.tw")
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

    /// 健康連結狀態：`checking` 是還沒問出授權結果（避免冷啟動瞬間閃出「未連結」）。
    enum HealthLinkState { case checking, linked, notLinked }

    // 今日健康摘要：只有 `.linked` 時才有真實資料，未連結一律不顯示數字。
    @Published private(set) var healthSummary: HealthSummary?
    @Published private(set) var healthLink: HealthLinkState = .checking

    let goalSteps = 8_000

    var todaySteps: Int { healthSummary?.steps ?? 0 }
    var activeMinutes: Int { healthSummary?.exerciseMinutes ?? 0 }
    var distanceText: String {
        let km = (healthSummary?.distanceMeters ?? 0) / 1_000.0
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
    private weak var envStore: AppEnvironmentStore?

    func configure(auth: AuthServicing, tasks: TasksServicing, profileStore: ProfileStoring,
                   health: HealthReading, envStore: AppEnvironmentStore) {
        guard self.auth == nil else { return }
        self.auth = auth
        self.tasks = tasks
        self.profileStore = profileStore
        self.health = health
        self.envStore = envStore
    }

    /// 讀取今日健康摘要（唯讀，需已授權）。未授權或讀取失敗都歸類為「未連結」，
    /// 由 UI 顯示淺灰半透明占位圖案，不視為錯誤、也不顯示假數字。
    func loadHealthSummary() async {
        guard let health else { return }
        await loadHealthSummary(using: health)
    }

    /// 剛切進示範模式時，ViewModel 還握著切換前的 reader，因此要能指定用哪一個。
    func loadHealthSummary(using health: HealthReading) async {
        guard await health.isAuthorized() else {
            healthLink = .notLinked
            healthSummary = nil
            return
        }
        do {
            healthSummary = try await health.summary(for: Date())
            healthLink = .linked
        } catch {
            healthLink = .notLinked
            healthSummary = nil
        }
    }

    /// 本地優先 + 節流：先秀快取；距上次更新未滿 60 秒（且已有資料）就不發 request。
    ///
    /// `force == true` 只發生在「剛登入成功」之後，因此遙測來源標成 `post_login`——
    /// 這是用來分辨「官網改版」與「session 過期」的關鍵：
    /// 剛登入完還解析失敗，就不可能是 session 過期了。
    func loadWeeklySummary(force: Bool = false) async {
        guard let tasks else { return }
        if currentWeekTask == nil, let cached = TasksCache.load() {
            currentWeekTask = Self.highlightedPeriod(in: cached)
        }
        guard force || TasksCache.canRefresh() || currentWeekTask == nil else { return }
        let hadCache = currentWeekTask != nil
        isLoadingSummary = currentWeekTask == nil
        defer { isLoadingSummary = false }
        let startedAt = DispatchTime.now()
        do {
            let periods = try await tasks.fetchTasks()
            currentWeekTask = Self.highlightedPeriod(in: periods)
            TasksCache.save(periods)
            TasksTelemetry.reportSuccess(
                source: force ? .postLogin : .homeRefresh,
                periods: periods,
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
        var hadCache = false
        if let cached = TasksCache.load() {
            currentWeekTask = Self.highlightedPeriod(in: cached)
            hasLoggedIn = true
            hadCache = true
        }
        Telemetry.setCrashKey(.tasksCache(hadCache ? (TasksCache.canRefresh() ? .stale : .fresh) : .none))
        Telemetry.setCrashKey(.sessionState(isProfileComplete ? (hadCache ? .cachedOnly : .loggedIn)
                                                             : .profileMissing))
        if isProfileComplete && !didAutoLogin {
            didAutoLogin = true
            // 節流：距上次更新未滿 60 秒且已有快取，就不發請求。
            if TasksCache.canRefresh() || currentWeekTask == nil {
                let startedAt = DispatchTime.now()
                do {
                    let periods = try await tasks?.fetchTasks() ?? []
                    guard !periods.isEmpty else { throw AppError.parsing("empty task list") }
                    hasLoggedIn = true
                    currentWeekTask = Self.highlightedPeriod(in: periods)
                    TasksCache.save(periods)
                    TasksTelemetry.reportSuccess(source: .homeBootstrap, periods: periods,
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
                if let periods = try? await envStore.environment.tasks.fetchTasks() {
                    currentWeekTask = Self.highlightedPeriod(in: periods)
                }
                await loadHealthSummary(using: envStore.environment.health)
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
            case .csrfNotFound, .unexpectedResponse, .parsing: return "官網回應異常，請稍後再試"
            case .notLoggedIn: return "尚未登入，請先完成一鍵登入"
            case .blockedEgress: return "偵測到非官方網域連線，已阻擋"
            }
        }
        return "發生未知錯誤，請稍後再試一次"
    }
}

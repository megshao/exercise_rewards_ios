import SwiftUI
import ExerciseRewardsKit

/// 我的券夾：列出已兌換（可使用）的加碼券與任務完成待兌換的期別。
/// - 已兌換 → 點「檢視券碼」開 VoucherView（每次都要 OTP 驗證後才顯示條碼）。
/// - 已兌換且使用者標記過「已使用」→ 移到最下方的「已使用」區，**不再顯示「檢視券碼」**。
///   官網沒有這個狀態，只能靠使用者自己標記（見 `VoucherUsage`）。
/// - 待兌換 → 點「去兌換」開 RedeemView（兌換的二次確認在 RedeemView 內）。
struct WalletView: View {
    @Environment(\.appEnvironment) private var environment
    /// 「已使用」標記的共用真相來源（見 `VoucherUsageStore`）。
    @EnvironmentObject private var voucherUsage: VoucherUsageStore
    /// 券碼頁關閉時要導回券夾，sheet 內容需要顯式注入（見 `TabRouter`）。
    @EnvironmentObject private var tabRouter: TabRouter
    @StateObject private var viewModel = WalletViewModel()
    @State private var voucherPeriod: TaskPeriod?
    @State private var redeemPeriod: TaskPeriod?

    var body: some View {
        VStack(spacing: 0) {
            // 5b：券夾沒有自己的快取，但重新整理失敗時上一輪的清單還在畫面上——
            // 同樣不能靜默沿用，掛 banner 說這是先前抓到的（位置比照 `TasksView`）。
            if viewModel.showsSiteHandoffBanner {
                SiteHandoffBanner(destination: .tasks) {
                    viewModel.isSiteHandoffBannerDismissed = true
                }
            }
            scrollContent
        }
        .background(Theme.Colors.background)
        .navigationTitle("我的券夾")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Telemetry.screenAppeared(.wallet) }
        .task {
            viewModel.configure(tasks: environment.tasks)
            if viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                await viewModel.refresh()
            }
        }
        // 不需要 onDismiss 重讀標記：`voucherUsage` 是共用的 `@Published`。
        .sheet(item: $voucherPeriod) { period in
            NavigationStack { VoucherView(taskID: period.id, source: .wallet, periodIndex: period.index) }
                .environment(\.appEnvironment, environment)
                .environmentObject(voucherUsage)
                .environmentObject(tabRouter)
        }
        // 上面那句「不需要 onDismiss」只適用於券碼 sheet——它只動本機的 `voucherUsage`。
        // 兌換動的是官網端狀態（該期變成 REDEEMED），不重抓的話這一期會一直留在
        // 「可兌換」區塊，跟 `TasksView`／`HomeView` 的兌換 sheet 是同一個道理。
        .sheet(item: $redeemPeriod, onDismiss: {
            Task { await viewModel.refresh() }
        }) { period in
            NavigationStack { RedeemView(taskID: period.id, periodIndex: period.index) }
                .environment(\.appEnvironment, environment)
                // RedeemView 兌換成功後會再開 VoucherView，那一頁要 voucherUsage。
                .environmentObject(voucherUsage)
                .environmentObject(tabRouter)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("已取得的加碼券，最多可獲得 14 張")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Colors.muted)

                if viewModel.isLoading && viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if viewModel.isSiteHandoff, viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                    // 5a：官網結構對不上——「請先回首頁登入」是錯誤歸因。券夾沒有單一 taskID，
                    // 交接到任務清單頁，官網那裡每一期的券都點得到。
                    SiteHandoffState(destination: .tasks) {
                        await viewModel.refresh()
                    }
                } else if let error = viewModel.errorMessage,
                          viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                    emptyOrError(icon: "exclamationmark.triangle.fill", text: error, showRetry: true)
                } else if viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                    emptyOrError(icon: "ticket",
                                 text: "目前沒有加碼券。\n完成任務並兌換後，加碼券會出現在這裡。",
                                 showRetry: false)
                } else {
                    if !viewModel.redeemable.isEmpty {
                        sectionTitle("可兌換")
                        ForEach(viewModel.redeemable, id: \.index) { period in
                            redeemableCard(period)
                        }
                    }
                    let unused = viewModel.redeemed.filter { !voucherUsage.isUsed($0) }
                    let used = viewModel.redeemed.filter { voucherUsage.isUsed($0) }
                    if !unused.isEmpty {
                        sectionTitle("可使用的加碼券")
                        ForEach(unused, id: \.index) { period in
                            voucherCard(period)
                        }
                    }
                    if !used.isEmpty {
                        sectionTitle("已使用")
                        ForEach(used, id: \.index) { period in
                            usedVoucherCard(period)
                        }
                    }
                }
            }
            .padding(20)
        }
        .refreshable { await viewModel.refresh() }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.displayFont(16, weight: .bold))
            .padding(.top, 4)
    }

    /// 已兌換的券卡：可檢視券碼（走 OTP）。
    private func voucherCard(_ period: TaskPeriod) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill").foregroundStyle(Theme.Colors.primary)
                    Text("第 \(period.index) 期加碼券")
                        .font(Theme.displayFont(15, weight: .bold))
                }
                Spacer()
                StatusBadge(text: "已兌換",
                            foreground: Theme.Colors.dim,
                            background: Color(hex: 0xEEF0F3))
            }
            Text("\(period.startDate) ~ \(period.endDate)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.muted)
            // 官網卡片上的「兌換內容：通路／品項」。官網原文，只顯示、不進遙測。
            if let summary = period.voucherSummary {
                Text(summary)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                voucherPeriod = period
            } label: {
                HStack {
                    Image(systemName: "qrcode")
                    Text("檢視券碼")
                }
            }
            .buttonStyle(.huihanPrimary)

            Button {
                toggleUsed(period)
            } label: {
                Text("標記為已使用")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.muted)
            }
            .accessibilityIdentifier("walletMarkUsed")
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 已標記為使用完畢的券：整張轉灰、**不提供「檢視券碼」**，只留「還原」。
    /// 標記是本機備忘，所以卡片上要講清楚它不影響官網。
    private func usedVoucherCard(_ period: TaskPeriod) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.dim)
                    Text("第 \(period.index) 期加碼券")
                        .font(Theme.displayFont(15, weight: .bold))
                        .foregroundStyle(Theme.Colors.muted)
                }
                Spacer()
                StatusBadge(text: "已使用",
                            foreground: Theme.Colors.dim,
                            background: Color(hex: 0xEEF0F3))
            }
            if let summary = period.voucherSummary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("你在 App 內標記為已使用（本機紀錄顯示，使用與否以條碼能否使用為主）。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.Colors.dim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                toggleUsed(period)
            } label: {
                Text("還原成未使用")
            }
            .accessibilityIdentifier("walletRestoreUsed")
            .buttonStyle(.huihanSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: 0xFAFBFC))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(Theme.Colors.line, lineWidth: 1)
        )
    }

    /// 任務完成待兌換：去兌換。
    private func redeemableCard(_ period: TaskPeriod) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("第 \(period.index) 期")
                    .font(Theme.displayFont(15, weight: .bold))
                Spacer()
                StatusBadge(text: "可兌換",
                            foreground: .white,
                            background: Theme.Colors.success)
            }
            Text("任務完成 · 尚未兌換")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.muted)
            Button {
                // 兌換本身在 RedeemView 有「確認兌換」二次確認，這裡不再多一道驗證。
                redeemPeriod = period
            } label: {
                HStack {
                    Image(systemName: "gift.fill")
                    Text("去兌換")
                }
            }
            .buttonStyle(.huihanPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 切換「已使用」標記。寫進共用 store，三個分頁會一起重畫。
    private func toggleUsed(_ period: TaskPeriod) {
        let used = voucherUsage.toggle(id: period.id)
        // E29：只送方向，不帶期別 UUID／期數／兌換內容。
        Telemetry.logEvent(.voucherMarkUsed(used: used))
    }

    private func emptyOrError(icon: String, text: String, showRetry: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Theme.Colors.dim)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
            if showRetry {
                Button { Task { await viewModel.refresh() } } label: { Text("重新載入") }
                    .buttonStyle(.huihanSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

@MainActor
final class WalletViewModel: ObservableObject {
    @Published var redeemed: [TaskPeriod] = []
    @Published var redeemable: [TaskPeriod] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// 這一次抓取是否撞上「官網結構對不上」（`SiteHandoff.shouldHandoff(_:)`）。
    /// 與 `errorMessage` 互斥：走接手畫面的錯誤不再套「請先回首頁登入」那句。
    @Published private(set) var isSiteHandoff = false
    /// 使用者關掉了頂端 banner。下一次抓取再失敗時要重新出現，所以每次 `refresh` 開頭歸零。
    @Published var isSiteHandoffBannerDismissed = false

    /// 畫面上還有上一輪的清單、又撞上改版、而且使用者還沒關掉——三個條件都成立才掛 banner。
    var showsSiteHandoffBanner: Bool {
        isSiteHandoff && !(redeemed.isEmpty && redeemable.isEmpty) && !isSiteHandoffBannerDismissed
    }

    private var tasks: TasksServicing?

    func configure(tasks: TasksServicing) {
        guard self.tasks == nil else { return }
        self.tasks = tasks
    }

    func refresh() async {
        guard let tasks else { return }
        let hadCache = !redeemed.isEmpty || !redeemable.isEmpty
        isLoading = true
        errorMessage = nil
        // 每次抓取都是一次新的判斷；banner 的 dismissed 一起歸零，這次再失敗才會重新出現。
        isSiteHandoff = false
        isSiteHandoffBannerDismissed = false
        defer { isLoading = false }
        let startedAt = DispatchTime.now()
        do {
            let periods = try await tasks.fetchTasks()
            redeemed = periods.filter { $0.state == .redeemed }
            redeemable = periods.filter { $0.state == .redeemable }
            TasksTelemetry.reportSuccess(source: .wallet, periods: periods,
                                         highlighted: HomeViewModel.highlightedPeriod(in: periods),
                                         hadCache: hadCache, startedAt: startedAt)
        } catch {
            TasksTelemetry.reportFailure(error, source: .wallet, hadCache: hadCache,
                                         startedAt: startedAt, sessionProbable: true)
            // 官網結構對不上走接手畫面（有清單就掛 banner）；其他錯誤才是原本那句。
            if SiteHandoff.shouldHandoff(error) {
                isSiteHandoff = true
            } else {
                errorMessage = "無法載入券夾，請先回首頁登入，或稍後重試。"
            }
        }
    }
}

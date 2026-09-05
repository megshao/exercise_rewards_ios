import SwiftUI
import SportsRewardsKit

/// 我的任務儀表板：垂直卡片列出 [TaskPeriod]，本週置頂高亮，下拉刷新。
/// 對齊 design/Tasks.dc.html。
struct TasksView: View {
    @Environment(\.appEnvironment) private var environment
    @EnvironmentObject private var sensitiveAuth: SensitiveAuthCoordinator
    @StateObject private var viewModel = TasksViewModel()
    @State private var screenshotPeriod: TaskPeriod?
    @State private var redeemPeriod: TaskPeriod?
    @State private var voucherPeriod: TaskPeriod?
    @State private var uploadPeriod: TaskPeriod?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if viewModel.isLoading && viewModel.periods.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let errorMessage = viewModel.errorMessage, viewModel.periods.isEmpty {
                    errorState(errorMessage)
                } else {
                    ForEach(viewModel.periods, id: \.index) { period in
                        TaskPeriodCard(
                            period: period,
                            isHighlighted: period.index == viewModel.highlightedPeriodIndex,
                            onRedeemTap: {
                                // 敏感動作再驗證：進入兌換頁前先過 Face ID（或 fallback）。
                                Task {
                                    if await sensitiveAuth.authorize(reason: "驗證身份以進行兌換") {
                                        redeemPeriod = period
                                    }
                                }
                            },
                            onScreenshotTap: { screenshotPeriod = period },
                            onVoucherTap: { voucherPeriod = period },
                            onUploadTap: { uploadPeriod = period }
                        )
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.Colors.background)
        .navigationTitle("我的任務")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh()
        }
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
        .sheet(item: $redeemPeriod) { period in
            NavigationStack {
                RedeemView(taskID: period.id, periodIndex: period.index)
            }
            .environment(\.appEnvironment, environment)
        }
        .sheet(item: $voucherPeriod) { period in
            NavigationStack {
                VoucherView(taskID: period.id)
            }
            .environment(\.appEnvironment, environment)
        }
        .sheet(item: $uploadPeriod) { period in
            NavigationStack {
                UploadView(taskID: period.id, periodIndex: period.index)
            }
            .environment(\.appEnvironment, environment)
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
                Task { await viewModel.refresh() }
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
    let onRedeemTap: () -> Void
    let onScreenshotTap: () -> Void
    let onVoucherTap: () -> Void
    let onUploadTap: () -> Void

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
                if isHighlighted, let remainingText = period.remainingText {
                    Text(remainingText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Colors.primaryDark)
                } else {
                    TaskStateBadge(state: period.state)
                }
            }

            if isHighlighted {
                TaskStateBadge(state: period.state)
            }

            if let uploadedAt = period.uploadedAt {
                Text(reviewSummary(uploadedAt: uploadedAt, reviewedAt: period.reviewedAt))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.muted)
            } else if period.state == .pendingReview, let remainingText = period.remainingText, !isHighlighted {
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
            Button {
                onUploadTap()
            } label: {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("上傳運動紀錄")
                }
            }
            .buttonStyle(.huihanPrimary)
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

                    if period.state == .redeemed {
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

// MARK: - ViewModel

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var periods: [TaskPeriod] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

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
    /// - Parameter force: 忽略節流（保留給明確需要立即更新的情境；一般下拉刷新用預設 false）。
    func refresh(force: Bool = false) async {
        guard let tasks else { return }
        // 1. 先顯示快取（若目前空）
        if periods.isEmpty, let cached = TasksCache.load() {
            periods = Self.sorted(cached)
        }
        // 2. 節流：未滿間隔且已有資料就不發請求
        guard force || TasksCache.canRefresh() || periods.isEmpty else { return }

        isLoading = periods.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await tasks.fetchTasks()
            periods = Self.sorted(fetched)
            TasksCache.save(fetched)
        } catch {
            // 有快取就靜默沿用；完全沒資料才顯示錯誤。
            if periods.isEmpty {
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

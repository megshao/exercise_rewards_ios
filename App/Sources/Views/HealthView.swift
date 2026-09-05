import SwiftUI
import SportsRewardsKit

/// 健康數據。串接 HealthKit（唯讀）：
/// 未授權時顯示「連結 Apple 健康」CTA；已授權顯示今日健康摘要與達標徽章。
///
/// HealthKit 數值只在本機
/// 顯示/判斷達標，**絕不離開裝置**——這裡沒有任何把健康數據送出網路、或用健康數據產生上傳
/// 圖卡的路徑。達標後只顯示一句文字導引使用者去「我的任務」用相簿截圖上傳
/// （HealthKit read-only, never transmitted）。
struct HealthView: View {
    @Environment(\.appEnvironment) private var environment
    @StateObject private var viewModel = HealthViewModel()

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                loadingView
            case .unauthorized:
                unauthorizedView
            case .ready:
                readyView
            case .error(let message):
                errorView(message)
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("健康數據")
        .navigationBarTitleDisplayMode(.inline)
        // E1：健康頁的 screen_view **不帶任何狀態參數**。
        // 「未授權 / 已連結 / 讀取失敗」看起來像無害的 UI 狀態，但 `ready` 的意思是
        // 「`summary()` 成功回傳了資料」——那是「這支裝置查得到 HealthKit 資料」的間接
        // 訊號，屬於 HealthKit 衍生資訊。只送「有人打開了健康頁」。
        .onAppear { Telemetry.screenAppeared(.health) }
        .task {
            viewModel.configure(health: environment.health)
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("讀取健康資料中…")
                .tint(Theme.Colors.primary)
            Spacer()
        }
    }

    // MARK: - Unauthorized

    private var unauthorizedView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.Colors.primary)
                .frame(width: 84, height: 84)
                .background(Theme.Colors.card2)
                .clipShape(Circle())

            Text("連結 Apple 健康")
                .font(Theme.displayFont(20, weight: .heavy))

            Text("授權讀取步數、距離、運動時間，才能查看今日健康摘要並判斷是否達標。\n本 App 僅讀取，不會寫入健康資料，且健康數據只在裝置本機顯示，不會被送出。")
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let message = viewModel.authorizationErrorMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                Task { await viewModel.requestAuthorizationTapped() }
            } label: {
                HStack {
                    Image(systemName: "heart.fill")
                    Text("連結 Apple 健康")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isLoading: viewModel.isRequestingAuthorization))
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
        .padding(20)
    }

    // MARK: - Ready

    private var readyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerBadge
                Text("\(viewModel.dateText) · 資料來源：Apple 健康")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Colors.muted)

                ringCard
                statRow

                if let evaluation = viewModel.evaluation, evaluation.isMet {
                    metCriteriaBanner(evaluation)
                }
            }
            .padding(20)
        }
    }

    private var headerBadge: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                Text("已連 Apple 健康")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(Theme.Colors.success)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Theme.Colors.successBackground)
            .clipShape(Capsule())
        }
    }

    private var ringCard: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(hex: 0xECEEF2), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: viewModel.stepsProgress)
                    .stroke(Theme.Colors.ringGradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 3) {
                    Text("\(viewModel.summary?.steps ?? 0)")
                        .font(Theme.displayFont(38, weight: .heavy))
                    Text("步 · 目標 8,000")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.muted)
                    Text("達標 \(viewModel.stepsPercentText)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.success)
                        .clipShape(Capsule())
                        .padding(.top, 6)
                }
            }
            .frame(width: 180, height: 180)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(radius: Theme.Radius.xlarge, padding: 22)
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            statCard(value: viewModel.distanceText, unit: "km", label: "步行距離")
            statCard(value: "\(viewModel.summary?.exerciseMinutes ?? 0)", unit: "分", label: "運動時間")
            statCard(value: viewModel.weeklyAverageText, unit: nil, label: "本週平均步數")
        }
    }

    private func statCard(value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.displayFont(20, weight: .heavy))
                if let unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.Colors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.Colors.line2, lineWidth: 1)
        )
    }

    /// 達標時只給一句文字導引去「我的任務」用相簿截圖上傳；不提供任何用 HealthKit 數據
    /// 產圖或送出網路的入口。
    private func metCriteriaBanner(_ evaluation: GoalEvaluation) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(Theme.Colors.success)
            VStack(alignment: .leading, spacing: 4) {
                Text("今日已符合任務條件")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: 0x186C3E))
                Text(evaluation.met.map(\.label).joined(separator: "、"))
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0x0D5730))
                Text("今日已達標，可到「我的任務」上傳截圖。")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0x186C3E))
            }
        }
        .padding(14)
        .background(Theme.Colors.successBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xB7E5CB), lineWidth: 1)
        )
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(Theme.Colors.danger)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("重試") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.huihanSecondary)
            Spacer()
            Spacer()
        }
    }
}

// MARK: - ViewModel

@MainActor
final class HealthViewModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case unauthorized
        case ready
        case error(String)
    }

    @Published private(set) var state: LoadState = .loading
    @Published private(set) var summary: HealthSummary?
    @Published private(set) var weeklyAverageSteps: Int?
    @Published var isRequestingAuthorization = false
    @Published var authorizationErrorMessage: String?

    private var health: HealthReading?
    private static let stepGoal = 8_000

    func configure(health: HealthReading) {
        guard self.health == nil else { return }
        self.health = health
    }

    var evaluation: GoalEvaluation? {
        guard let summary else { return nil }
        return GoalEvaluator.evaluate(summary)
    }

    var stepsProgress: Double {
        guard let summary else { return 0 }
        return min(1.0, Double(summary.steps) / Double(Self.stepGoal))
    }

    var stepsPercentText: String {
        guard let summary else { return "0%" }
        let pct = Int((Double(summary.steps) / Double(Self.stepGoal) * 100).rounded())
        return "\(pct)%"
    }

    var distanceText: String {
        guard let summary else { return "0.0" }
        return String(format: "%.1f", summary.distanceKm)
    }

    /// 圓環中央的步數是用 `Text("\(Int)")` 畫的，SwiftUI 會自動補千分位（9,688）；
    /// 這裡回傳的是純字串，得自己 `formatted()` 一次，否則同一畫面會出現 9,688 / 9688 兩種寫法。
    var weeklyAverageText: String {
        guard let weeklyAverageSteps else { return "—" }
        return weeklyAverageSteps.formatted()
    }

    var dateText: String {
        guard let date = summary?.date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy/MM/dd（EEEEE）"
        return formatter.string(from: date)
    }

    /// 初次載入 / 下拉重新整理：先確認授權，已授權才查資料。
    func load() async {
        guard let health else { return }
        state = .loading
        let authorized = await health.isAuthorized()
        guard authorized else {
            state = .unauthorized
            return
        }
        await fetchSummary()
    }

    private func fetchSummary() async {
        guard let health else { return }
        do {
            let today = try await health.summary(for: Date())
            summary = today
            await fetchWeeklyAverage()
            state = .ready
        } catch {
            state = .error("讀取健康資料失敗，請稍後再試")
        }
    }

    /// 近 7 天（含今日）步數平均，僅供顯示參考；單筆查詢失敗（給 0）不視為整體錯誤。
    private func fetchWeeklyAverage() async {
        guard let health else { return }
        let calendar = Calendar.current
        var total = 0
        var count = 0
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            if let daySummary = try? await health.summary(for: date) {
                total += daySummary.steps
                count += 1
            }
        }
        weeklyAverageSteps = count > 0 ? total / count : nil
    }

    /// 按下「連結 Apple 健康」。
    ///
    /// **只埋這個動作，不埋結果。** 這裡是 HealthKit 相關唯一被允許的事件：按鈕按下的
    /// 當下 HealthKit 還沒被呼叫，送出的是純粹的 UI 動作。
    /// 底下 `requestAuthorization()` 的回傳／throw **刻意不埋**（見 `Telemetry.swift` 的 E10）：
    /// 那是「從 HealthKit API 取得的資訊」，`HKError` 碼更是直接揭露授權狀態，
    /// 依 App Store Review Guideline 5.1.3(i) 不得分享給第三方。
    /// 「有多少人願意連結健康」用本事件的次數就估得出來。
    func requestAuthorizationTapped() async {
        guard let health else { return }
        // E9：無參數。
        Telemetry.logEvent(.healthLinkTap)
        isRequestingAuthorization = true
        authorizationErrorMessage = nil
        defer { isRequestingAuthorization = false }
        do {
            try await health.requestAuthorization()
            await load()
        } catch {
            authorizationErrorMessage = "無法取得 Apple 健康授權，請至「設定 > 隱私權與安全性 > 健康」開啟"
        }
    }
}

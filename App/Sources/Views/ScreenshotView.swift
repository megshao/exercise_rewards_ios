import SwiftUI
import SportsRewardsKit

/// 看截圖：讀取 `TasksServicing.screenshotImageURL` 解析出的 S3 presigned 圖片網址，
/// 直接用 `AsyncImage` 顯示。
///
/// 刻意範圍例外：這裡顯示的圖片只會是「使用者本人上傳到官方 S3 儲存」的 presigned URL
/// （網址自帶簽章、無需登入即可讀取），因此可以直接讓 `AsyncImage` 連線該 S3 host——
/// SportsRewardsKit 的 500.gov.tw 白名單只擋「本 client 主動連線」的請求，這裡只是把官方站回傳
/// 的字串網址交給系統圖片載入器，過程中不會夾帶任何 cookie／憑證出去。
struct ScreenshotView: View {
    let taskID: String

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var imageURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    // 縮放狀態：預設 fit（scale 1），雙指可放大、雙擊還原。
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    /// E14 每次進入畫面只送一次：`AsyncImage` 的 phase 會多次變動，不擋會洗版。
    @State private var didReportOutcome = false

    private let maxScale: CGFloat = 4

    var body: some View {
        Group {
            if let imageURL {
                GeometryReader { geo in
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: geo.size.width, height: geo.size.height)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .scaleEffect(scale * pinch)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .contentShape(Rectangle())
                                .gesture(
                                    MagnificationGesture()
                                        .updating($pinch) { value, state, _ in state = value }
                                        .onEnded { value in
                                            scale = min(max(scale * value, 1), maxScale)
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        scale = scale > 1 ? 1 : 2
                                    }
                                }
                                .onAppear { report(.ok) }
                        case .failure:
                            errorState("圖片載入失敗，請稍後再試")
                                .frame(width: geo.size.width, height: geo.size.height)
                                .onAppear { report(.imageFailed) }
                        @unknown default:
                            errorState("圖片載入失敗，請稍後再試")
                                .frame(width: geo.size.width, height: geo.size.height)
                                .onAppear { report(.imageFailed) }
                        }
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                errorState(errorMessage ?? "無法載入截圖")
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("上傳截圖")
        .navigationBarTitleDisplayMode(.inline)
        // E1：不帶 taskID。
        .onAppear { Telemetry.screenAppeared(.screenshot) }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("關閉") { dismiss() }
            }
        }
        .task {
            await load()
        }
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
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(20)
    }

    /// E14：**S3 presigned URL、它的 host 與查詢字串一律不送**——presigned URL 內含
    /// bucket 名與簽章，是官方站識別碼。只送四選一的結果分類。
    private func report(_ outcome: ScreenshotOutcome) {
        guard !didReportOutcome else { return }
        didReportOutcome = true
        Telemetry.logEvent(.screenshotView(outcome: outcome))
    }

    private func load() async {
        guard !taskID.isEmpty else {
            isLoading = false
            errorMessage = "找不到這期任務的截圖"
            report(.noId)
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            imageURL = try await environment.tasks.screenshotImageURL(taskID: taskID)
        } catch {
            errorMessage = "無法載入截圖，請確認網路連線後重試"
            Telemetry.reportFailure(error, endpoint: .screenshot)
            report(.urlFailed)
        }
    }
}

import SwiftUI
import PhotosUI
import UIKit
import SportsRewardsKit

/// 上傳運動紀錄。
///
/// 隱私設計：
/// 不用 HealthKit 數據產圖上傳，改成讓使用者從相簿**自選**一張運動紀錄截圖 → 預覽 →
/// 「確認上傳」。這裡完全不會讀取／使用 HealthKit 資料（HealthKit read-only, never
/// transmitted，健康數據只在 HealthView/HomeView 本機顯示）。
struct UploadView: View {
    let taskID: String
    let periodIndex: Int?

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = UploadViewModel()
    @State private var pickerItem: PhotosPickerItem?

    init(taskID: String, periodIndex: Int? = nil) {
        self.taskID = taskID
        self.periodIndex = periodIndex
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                instructionBanner

                if let result = viewModel.result {
                    resultView(result)
                } else {
                    pickerSection

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.Colors.danger)
                    }

                    if let image = viewModel.previewImage {
                        previewCard(image)
                        confirmButton
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.Colors.background)
        .navigationTitle(periodIndex.map { "上傳運動紀錄 · 第 \($0) 期" } ?? "上傳運動紀錄")
        .navigationBarTitleDisplayMode(.inline)
        // E1：不帶 taskID（期別 UUID）。要知道是第幾期，看 upload_submit 的 period_index。
        .onAppear { Telemetry.screenAppeared(.upload) }
        .task {
            viewModel.configure(upload: environment.upload, taskID: taskID, periodIndex: periodIndex)
        }
        .onChange(of: pickerItem) { newItem in
            Task { await viewModel.loadPickedImage(newItem) }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("關閉") { dismiss() }
            }
        }
    }

    private var instructionBanner: some View {
        Text("每期限上傳一次截圖。請從相簿選一張這期運動紀錄的截圖（例如運動 App 的統計畫面），確認後送出。")
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.Colors.muted)
            .padding(12)
            .background(Theme.Colors.card2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var pickerSection: some View {
        // 先在 View（main actor）取值成本地布林，PhotosPicker 的 label closure 只捕捉它，
        // 避免從 closure 直接參照 main-actor 隔離的 viewModel 屬性（Swift 6 並發 warning）。
        let hasImage = viewModel.previewImage != nil
        return PhotosPicker(selection: $pickerItem, matching: .images) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                Text(hasImage ? "重新選擇截圖" : "從相簿選擇截圖")
            }
        }
        .buttonStyle(.huihanSecondary)
        .disabled(viewModel.isUploading)
    }

    private func previewCard(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.Colors.line2, lineWidth: 1)
            )
    }

    private var confirmButton: some View {
        Button {
            Task { await viewModel.confirmUpload() }
        } label: {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                Text("確認上傳")
            }
        }
        .buttonStyle(PrimaryButtonStyle(isLoading: viewModel.isUploading))
    }

    private func resultView(_ result: UploadResult) -> some View {
        VStack(spacing: 12) {
            Image(systemName: result.submitted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(result.submitted ? Theme.Colors.success : Theme.Colors.danger)
            Text(result.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)

            if !result.submitted {
                Button {
                    viewModel.reset()
                } label: {
                    Text("重新選擇")
                }
                .buttonStyle(.huihanSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

// MARK: - ViewModel

@MainActor
final class UploadViewModel: ObservableObject {
    @Published var previewImage: UIImage?
    @Published var isUploading = false
    @Published var errorMessage: String?
    @Published var result: UploadResult?

    private var upload: UploadServicing?
    private var taskID = ""
    /// 活動週次（1–14）。遙測只送這個，**不送 `taskID`（期別 UUID）**。
    private var periodIndex: Int?
    private var imageData: Data?

    func configure(upload: UploadServicing, taskID: String, periodIndex: Int? = nil) {
        guard self.upload == nil else { return }
        self.upload = upload
        self.taskID = taskID
        self.periodIndex = periodIndex
        Telemetry.setCrashKey(.uploadStage(.idle))
    }

    /// 讀取使用者從相簿選取的截圖。只接受圖片資料本身，不去讀取任何 HealthKit 或個資欄位。
    ///
    /// **E11 只送二元結果（picked / unreadable）。** 刻意不送的東西：`data.count`、
    /// `UIImage.size`、原始格式（HEIC/JPEG）、`jpegDataUnder5MB` 的壓縮迭代次數
    /// （迭代次數可以反推檔案大小，是衍生資訊）、`PhotosPickerItem.itemIdentifier`、EXIF。
    /// 使用者的照片是 User Content，關於它的任何測量值都不該離開裝置。
    /// 同理，選圖失敗**不進 Crashlytics 非致命錯誤**——那是關於使用者檔案的錯誤。
    func loadPickedImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        errorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "無法讀取這張圖片，請重新選擇"
                Telemetry.logEvent(.uploadPick(outcome: .unreadable))
                return
            }
            // 統一轉成 JPEG（官網只收 JPG/PNG）並壓到 5MB 以內，避免相簿原檔是 HEIC 被拒。
            //
            // **重新編碼失敗時一律報錯，絕不 fallback 送原檔。** 相簿原檔帶著完整 EXIF，
            // 其中包含 GPS 座標——那是「使用者在哪裡運動」的精確位置，比運動紀錄本身
            // 更敏感，而且使用者按「確認上傳」時完全不會預期它被一起送出去。
            // 重新用 `UIImage.jpegData` 編碼會把 EXIF 整段丟掉，這是本流程唯一的去識別化
            // 手段，所以它不能有旁路。（原檔也可能是 HEIC/PNG，跟固定送出的
            // `screenshot.jpg` / `image/jpeg` 對不上，本來就不該當 fallback。）
            guard let jpeg = Self.jpegDataUnder5MB(image) else {
                errorMessage = "圖片處理失敗，請換一張圖片再試"
                Telemetry.logEvent(.uploadPick(outcome: .unreadable))
                return
            }
            imageData = jpeg
            previewImage = image
            Telemetry.setCrashKey(.uploadStage(.picked))
            Telemetry.logEvent(.uploadPick(outcome: .picked))
        } catch {
            errorMessage = "無法讀取這張圖片，請重新選擇"
            Telemetry.logEvent(.uploadPick(outcome: .unreadable))
        }
    }

    /// 把圖片編成 ≤5MB 的 JPEG；必要時逐步降畫質。
    /// 回傳 nil（`jpegData` 全數失敗）時呼叫端必須報錯——**不可退回原檔**，
    /// 原檔帶 EXIF/GPS，重新編碼正是拿掉它們的地方。
    static func jpegDataUnder5MB(_ image: UIImage) -> Data? {
        let limit = 5 * 1024 * 1024
        for q in stride(from: 0.9, through: 0.3, by: -0.1) {
            if let d = image.jpegData(compressionQuality: q), d.count <= limit {
                return d
            }
        }
        return image.jpegData(compressionQuality: 0.3)
    }

    /// 送出使用者自選的截圖（真實 multipart POST /member/upload，file 欄位 screenshot）。
    func confirmUpload() async {
        guard let upload, let imageData else { return }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        Telemetry.setCrashKey(.uploadStage(.uploading))
        // E12：只有活動週次。沒有任何檔案資訊。
        Telemetry.logEvent(.uploadSubmit(periodIndex: periodIndex))
        let startedAt = DispatchTime.now()
        do {
            let uploadResult = try await upload.upload(
                taskID: taskID.isEmpty ? nil : taskID,
                imageData: imageData,
                fileName: "screenshot.jpg"
            )
            result = uploadResult
            Telemetry.setCrashKey(.uploadStage(.done))
            // E13：官網 `.notice--error` 的原文只留在 `uploadResult.message` 給畫面用，
            // 這裡送的是 `UploadFailure` 分類。
            Telemetry.logEvent(.uploadResult(outcome: Self.outcome(for: uploadResult),
                                             periodIndex: periodIndex,
                                             durationMs: Telemetry.elapsedMs(since: startedAt)))
            // 上傳端點回了非 200／302。「頁面沒有 file 欄位」不算錯誤（當期不可上傳是常態）。
            if case .httpError(let status) = uploadResult.failure {
                Telemetry.recordNonFatal(.upload, endpoint: .upload, status: status)
            }
        } catch {
            result = UploadResult(submitted: false, message: "上傳失敗，請稍後再試")
            Telemetry.setCrashKey(.uploadStage(.done))
            let reason = Telemetry.reportFailure(error, endpoint: .upload)
            Telemetry.logEvent(.uploadResult(outcome: Self.outcome(for: reason),
                                             periodIndex: periodIndex,
                                             durationMs: Telemetry.elapsedMs(since: startedAt)))
        }
    }

    /// `UploadResult` → 遙測分類。
    private static func outcome(for result: UploadResult) -> UploadOutcome {
        guard let failure = result.failure else {
            return result.submitted ? .submitted : .unknown
        }
        switch failure {
        case .windowClosed: return .windowClosed
        case .csrfMissing: return .csrfMissing
        case .siteRejected: return .siteRejected
        case .httpError: return .httpError
        }
    }

    /// throw 出來的錯誤 → 遙測分類。
    private static func outcome(for reason: FailReason) -> UploadOutcome {
        switch reason {
        case .network: return .network
        case .csrfMissing: return .csrfMissing
        case .siteStatus, .redirectLoop, .blockedEgress: return .httpError
        case .siteParse, .sessionProbable: return .siteRejected
        default: return .unknown
        }
    }

    func reset() {
        result = nil
        previewImage = nil
        imageData = nil
        errorMessage = nil
        Telemetry.setCrashKey(.uploadStage(.idle))
    }
}

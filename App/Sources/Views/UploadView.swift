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
        .task {
            viewModel.configure(upload: environment.upload, taskID: taskID)
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
    private var imageData: Data?

    func configure(upload: UploadServicing, taskID: String) {
        guard self.upload == nil else { return }
        self.upload = upload
        self.taskID = taskID
    }

    /// 讀取使用者從相簿選取的截圖。只接受圖片資料本身，不去讀取任何 HealthKit 或個資欄位。
    func loadPickedImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        errorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "無法讀取這張圖片，請重新選擇"
                return
            }
            // 統一轉成 JPEG（官網只收 JPG/PNG）並壓到 5MB 以內，避免相簿原檔是 HEIC 被拒。
            imageData = Self.jpegDataUnder5MB(image) ?? data
            previewImage = image
        } catch {
            errorMessage = "無法讀取這張圖片，請重新選擇"
        }
    }

    /// 把圖片編成 ≤5MB 的 JPEG；必要時逐步降畫質。
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
        do {
            result = try await upload.upload(
                taskID: taskID.isEmpty ? nil : taskID,
                imageData: imageData,
                fileName: "screenshot.jpg"
            )
        } catch {
            result = UploadResult(submitted: false, message: "上傳失敗，請稍後再試")
        }
    }

    func reset() {
        result = nil
        previewImage = nil
        imageData = nil
        errorMessage = nil
    }
}

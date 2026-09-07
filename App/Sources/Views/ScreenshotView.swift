import SwiftUI
import UIKit
import ExerciseRewardsKit

/// 看截圖：讀取 `TasksServicing.screenshotImageURL` 解析出的圖片網址，用**專用的
/// `URLSession`** 下載後以 `Image(uiImage:)` 顯示。
///
/// 刻意範圍例外：這裡顯示的圖片只會是「使用者本人上傳到官方站儲存」的簽章網址
/// （網址自帶簽章、無需登入即可讀取），網域由官方站決定。ExerciseRewardsKit 的
/// 500.gov.tw 白名單只擋「`URLSessionHTTPClient` 主動發出」的請求，所以這條路徑
/// 另外有兩道自己的關卡：
/// 1. `TasksService.isAllowedScreenshotImageURL`：302 `Location` 必須是 https，
///    且 host 在官方站白名單或官方圖片儲存網域內，否則丟 `blockedEgress`。
/// 2. 本檔的 `ScreenshotImageLoader`：cookie-less、不落盤的專用 session。
///
/// **為什麼不用 `AsyncImage`**：`AsyncImage` 走的是 `URLSession.shared`，
/// 而 `URLSession.shared` 的 cookie jar 就是 `HTTPCookieStorage.shared`——和
/// `URLSessionHTTPClient` 那個 `.default` session 是**同一個 jar**。讓 cookie 不外洩的
/// 是 cookie 自己的 domain scope（`500.gov.tw`），不是「這條路徑沒有 cookie」。
/// 這個差別在同源情境（`Location` 指回 500.gov.tw）就會現形：`AsyncImage` 會帶著
/// 登入 cookie 發出那個 GET。此外 `URLSession.shared` 用 `URLCache.shared`，
/// 會把圖片以網址為 key 落盤到 `Library/Caches`——那是使用者的運動紀錄截圖
/// （可能有姓名、路線），跟 `URLSessionHTTPClient`「頁面內容一律不進 URL cache」
/// 的原則不一致。所以這裡自己開一個 session，兩件事一次解決。
struct ScreenshotView: View {
    let taskID: String

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    // 縮放狀態：預設 fit（scale 1），雙指可放大、雙擊還原。
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    /// E14 每次進入畫面只送一次。
    @State private var didReportOutcome = false

    private let maxScale: CGFloat = 4

    var body: some View {
        Group {
            if let image {
                GeometryReader { geo in
                    Image(uiImage: image)
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

    /// E14：**圖片網址、它的 host 與查詢字串一律不送**——簽章網址內含 bucket 名與簽章，
    /// 是官方站識別碼。只送四選一的結果分類。
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

        let url: URL
        do {
            url = try await environment.tasks.screenshotImageURL(taskID: taskID)
        } catch {
            errorMessage = "無法載入截圖，請確認網路連線後重試"
            Telemetry.reportFailure(error, endpoint: .screenshot)
            report(.urlFailed)
            return
        }

        do {
            image = try await ScreenshotImageLoader.load(url)
            report(.ok)
        } catch {
            // 圖片下載失敗**不進 Telemetry.reportFailure**：這條路徑的對面是官方站指定的
            // 第三方圖床，它的 URLError 不是「官網改版」訊號，只送結果分類。
            errorMessage = "圖片載入失敗，請稍後再試"
            report(.imageFailed)
        }
    }
}

/// 截圖圖片的專用下載器。
///
/// 三件事跟 `URLSession.shared`／`AsyncImage` 不同，每一件都是刻意的：
/// - `ephemeral` 且 `httpCookieStorage = nil`、`httpShouldSetCookies = false`：
///   這條路徑**真的**沒有 cookie，不必依賴 domain scope 這個間接保證。
/// - `urlCache = nil`：使用者的運動紀錄截圖不落盤到 `Library/Caches`。
/// - 大小上限：避免惡意／異常回應把整份 body 讀進記憶體。
enum ScreenshotImageLoader {
    /// 圖片大小上限。上傳端本來就壓在 5 MB 以內，這裡留四倍餘裕。
    static let maxImageBytes = 20 * 1024 * 1024

    enum LoadError: Error {
        case badStatus(Int)
        case tooLarge(Int)
        case notAnImage
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    static func load(_ url: URL) async throws -> UIImage {
        // 示範模式回傳的是 App bundle 內附的 file URL（`MockTasksService`），
        // 不走網路——示範模式絕不能連外。
        if url.isFileURL {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard let image = UIImage(data: data) else { throw LoadError.notAnImage }
            return image
        }

        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LoadError.badStatus(http.statusCode)
        }
        guard data.count <= maxImageBytes else { throw LoadError.tooLarge(data.count) }
        guard let image = UIImage(data: data) else { throw LoadError.notAnImage }
        return image
    }
}

import Foundation

/// 廠商品項目錄的**離線備份**來源。
///
/// ## 為什麼需要它
///
/// 已兌換的期別在官網上沒有兌換頁了（見 `TaskParser` 的 id 註解與
/// `spec/redeem-flow-capture.md`），而 `intro/vendor-*.html` 的連結只長在兌換頁上。
/// 所以券夾要在已兌換的券卡上提供「查看可兌換品項」，就需要一份不依賴那一頁的
/// 「廠商名 → introPath」對應。這份備份同時也在官網品項頁載不到時接手顯示內容。
///
/// ## 這是全 App 唯一允許離開 500.gov.tw 的網路請求
///
/// **刻意不重用 `URLSessionHTTPClient`**：那一支持有登入後的 cookie jar，而它的主機
/// 白名單（`SiteConfig.host`）正是防止憑證外流的機制。把 github.io 加進那份白名單，
/// 等於讓帶著 JSESSIONID 的 session 有機會連上第三方主機。
///
/// 因此這裡自己開一個 **ephemeral、無 cookie、無憑證**的 `URLSession`，
/// 而且只認一個硬編碼的主機與路徑。兩邊的信任邊界維持分離。
///
/// ## 這份資料的性質
///
/// - **只用於顯示，不參與送出**：沒有 item id、沒有 vendorId、沒有 `_csrf`。
///   送出兌換一律解析當下的官網頁面，所以這裡的內容在結構上就不可能被送回官網。
/// - **是快照，不是即時資料**：官網品項頁自己就寫著「實際可兌換品項、供應狀況及
///   門市庫存，依各門市現場公告為準」。呼叫端顯示備份內容時**必須**一併顯示
///   `capturedAt`（見 `VendorCatalogBackup.capturedAt`）。
/// - **不含任何個資**：期別 UUID 屬官方站識別碼，一個都不在裡面。
public protocol VendorCatalogFetching: Sendable {
    func fetch() async throws -> VendorCatalogBackup
}

/// 備份目錄的解析結果。
public struct VendorCatalogBackup: Equatable, Sendable {
    /// 快照日期（`yyyy-MM-dd`）。顯示備份內容時必須讓使用者看到這個日期。
    public let capturedAt: String
    public let vendors: [Vendor]

    public struct Vendor: Equatable, Sendable {
        /// 兌換頁上印的廠商名，用來與 `TaskPeriod.voucherSummary` 的開頭比對。
        public let vendorName: String
        /// 兌換頁那一列連結的 base-relative path，原封搬運、不由 vendorId 拼出。
        public let introPath: String
        /// 直接組成 Kit 既有的 `VendorIntro`，讓畫面層不必分辨資料來自官網還是備份。
        public let intro: VendorIntro
    }

    public init(capturedAt: String, vendors: [Vendor]) {
        self.capturedAt = capturedAt
        self.vendors = vendors
    }

    /// 依廠商名找出備份。比對是**完全相等**——模糊比對留給呼叫端決定
    /// （`voucherSummary` 的開頭比對在 `WalletViewModel`）。
    public func vendor(named name: String) -> Vendor? {
        vendors.first { $0.vendorName == name }
    }

    /// 依 introPath 找出備份。品項頁載入失敗時用這一支——路徑是精確鍵，
    /// 比廠商名可靠（廠商名在兌換頁與品項頁的寫法可能不同，例如「全聯」對「全聯福利中心」）。
    public func vendor(introPath path: String) -> Vendor? {
        vendors.first { $0.introPath == path }
    }
}

public final class VendorCatalogService: VendorCatalogFetching {
    /// 備份檔的固定位置。**只有這一個主機、這一個路徑**。
    public static let defaultURL = URL(
        string: "https://megshao.github.io/exercise_rewards_ios/vendor-catalog.json")!

    /// 備份檔約 70 KB；上限給到 1 MB 已經非常寬鬆。超過就當異常，不解碼。
    private static let maxBytes = 1_048_576

    private let url: URL
    private let session: URLSession
    private let log = SecureLog(.network)

    public init(url: URL = VendorCatalogService.defaultURL) {
        self.url = url
        // ephemeral：不落地 cookie、不落地 cache、不共用任何憑證。
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: config)
    }

    public func fetch() async throws -> VendorCatalogBackup {
        // 主機再確認一次。URL 是編譯期常數，但這道檢查讓「日後有人把它改成可注入」
        // 不會靜默變成任意主機都能連。
        guard url.scheme == "https", url.host == VendorCatalogService.defaultURL.host else {
            throw AppError.blockedEgress(url.host ?? "unknown")
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.unexpectedResponse(0)
        }
        guard http.statusCode == 200 else {
            throw AppError.unexpectedResponse(http.statusCode)
        }
        guard data.count <= VendorCatalogService.maxBytes else {
            throw AppError.responseTooLarge(data.count)
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.schemaVersion == 1 else {
            // 版本不合就當沒有備份。舊版 App 不該猜新格式的意思。
            log.error("vendor catalog schemaVersion mismatch")
            throw AppError.parsing("unsupported vendor catalog schemaVersion")
        }
        return payload.model()
    }
}

// MARK: - 解碼

/// JSON 的線上格式。刻意與 `VendorIntro` 分開：備份檔的形狀由
/// `Scripts/capture-vendor-catalog.py` 決定，不該綁著畫面用的模型一起改。
private struct Payload: Decodable {
    let schemaVersion: Int
    let capturedAt: String
    let vendors: [Vendor]

    struct Vendor: Decodable {
        let vendorName: String
        let introPath: String
        let catalog: Catalog?
    }

    struct Catalog: Decodable {
        /// `full`＝官網逐項列出；`examples`＝官網只給舉例（全聯／萬家福・樂家康）。
        let listing: String
        let introTitle: String?
        let notice: String?
        let groups: [Group]
    }

    struct Group: Decodable {
        /// 品項頁上的分組標題（萊爾富分成「商品券超值加碼品項」與「50元加碼券可兌換品項」）。
        /// 多數廠商沒有分組，這時是 nil。
        let title: String?
        let categories: [Category]
    }

    struct Category: Decodable {
        let name: String
        let items: [String]?
        let examples: String?
        let statedCount: Int?
    }

    func model() -> VendorCatalogBackup {
        VendorCatalogBackup(
            capturedAt: capturedAt,
            vendors: vendors.compactMap { vendor in
                // 路徑不合形狀的一律丟掉：這個值會被拿去組官網網址。
                guard VendorCatalogService.isValidIntroPath(vendor.introPath),
                      let catalog = vendor.catalog else { return nil }
                return VendorCatalogBackup.Vendor(
                    vendorName: vendor.vendorName,
                    introPath: vendor.introPath,
                    intro: VendorIntro(
                        title: catalog.introTitle ?? vendor.vendorName,
                        subtitle: nil,
                        categories: catalog.groups.flatMap { group in
                            group.categories.map { category in
                                VendorIntroCategory(
                                    // 有分組時把組名併進分類名，否則萊爾富的「果昔」「雞胸肉」
                                    // 會在兩組間互相覆蓋（`VendorIntroCategory.id` 就是 name）。
                                    name: group.title.map { "\($0)・\(category.name)" } ?? category.name,
                                    items: category.items ?? [],
                                    examples: category.examples,
                                    statedCount: category.statedCount
                                )
                            }
                        },
                        notices: catalog.notice.map { [$0] } ?? [],
                        layout: catalog.listing == "examples" ? .categoryTable : .itemList
                    )
                )
            }
        )
    }
}

extension VendorCatalogService {
    /// 與 `RedeemParser` 接受的形狀一致：base-relative、限定 `/intro/*.html`。
    /// 備份檔是外部輸入，路徑一律重新驗證。
    static func isValidIntroPath(_ path: String) -> Bool {
        guard path.count <= 200, path.hasPrefix("/intro/"), path.hasSuffix(".html"),
              !path.contains(".."), !path.contains("?"), !path.contains("#"),
              !path.contains("//") else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./")
        return path.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

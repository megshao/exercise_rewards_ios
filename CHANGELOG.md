# Changelog

本檔案記錄 Sports Rewards（bundle id `com.megshao.sportsrewards`）的所有重要變更。
格式依循 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，版本號依循 [語意化版本](https://semver.org/lang/zh-TW/)。

---

## [1.0.0] - 2026-09-05

首次公開發行。iOS 16.0 以上、僅 iPhone、僅直向、介面固定繁體中文（zh-Hant）。
本 App 為非官方個人輔助工具，與運動部及任何政府機關無隸屬、合作或授權關係。

### Added

- **一鍵登入官方「我的任務」**：身分證號、出生日期、手機號碼填一次，之後直接登入 500.gov.tw 的會員區，不用每次重打。
- **首次啟動導覽與登入流程**：歡迎頁 → 三欄位表單 → 送出即驗證。查到「此身分證尚未註冊」時，改為提示並以外部 Safari 開啟官網註冊頁（App 本身不做註冊、不碰身分驗證）。
- **任務儀表板**：一次呈現 14 期任務的狀態（尚未開始／可上傳／待審核／可兌換／已兌換）、開放期間與倒數，本週置頂，可下拉刷新，離線時顯示上次快取。
- **今日健康摘要**：連結 Apple 健康後顯示今日步數、步行與跑步距離、運動時間，並判斷是否達到活動門檻（單日 8,000 步／健走 30 分／跑步 5 公里）。
- **上傳運動紀錄**：從相簿挑選截圖，直接以 multipart 送到當期任務（file 欄位 `screenshot`），每期限一次。
- **兌換加碼券**：選擇合作商家與品項送出兌換，後續以簡訊驗證取得券碼。
- **券夾**：集中檢視已取得的加碼券，可再次出示 QR／一維條碼給店家掃描。
- **「我的資料」頁**：檢視與編輯本機個資、遮罩顯示、頁首三點隱私聲明、「立即清除本機資料」（含二次確認，清除後回到初次設定）。
- **出生日期選擇器**：自製「年／月／日」三欄滾輪，可切換民國／西元（預設民國），底部同時顯示雙年份；換月自動夾住不存在的日期。
- **示範模式（Demo Mode）**：在登入表單輸入指定的示範三碼即進入全 mock 環境，不發任何網路請求、不寫 Keychain，畫面常駐「示範模式」橫幅，並可在「我的資料」一鍵離開。此模式提供給 App Store 審查員實測完整流程，示範三碼與 App Store Connect 的示範帳號欄位同步。示範模式下遙測一律關閉（`Telemetry` 中唯一沒有 bypass 的閘門，SDK 層的收集開關也會一併關掉），即使使用者先前打開過統計開關也一樣。
- **匿名使用統計與當機回報（Firebase Analytics + Crashlytics，預設關閉）**：新增「我的資料 › 安全與隱私 › 傳送匿名使用統計」開關。**出廠是關的**，使用者自己打開之前，一個位元組都不會送到 Google——`Info.plist` 的 `FIREBASE_ANALYTICS_COLLECTION_ENABLED`、`FirebaseCrashlyticsCollectionEnabled`、`GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED`、`GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS` 四個旗標全為 `false`。開啟後送出的是匿名操作事件（哪個畫面、哪一步失敗）與當機報告；**不含身分證號、出生日期、手機號碼，也不含任何 Apple 健康的數值或由步數推導出來的結論**。隨時可關，關掉即刻停止收集。
- **開源**：全部程式碼以 MIT 授權公開，核心邏輯抽成 `SportsRewardsKit` Swift Package，可 headless `swift build` / `swift test`。

### Changed

- **App Store 顯示名定為 `Sports Rewards`**：活動名「揮汗有禮」不作為 App 名稱，避免被誤認為官方 App。
- **個資最小化為三個欄位**：只收登入必要的身分證號、出生日期、手機號碼；姓名、Email、健保卡卡號一律不再收集（資料模型欄位保留但永遠為空）。
- **安全與隱私設定併入「我的資料」頁**：移除獨立的「資安中心」子頁，本機資料說明與清除功能少一層導覽即可操作。
- **首頁步數環改為三態**（確認中／已連結／未連結）：未連結時顯示淺灰虛線占位環與「尚未連結 Apple 健康」，不再出現任何示意用的假步數，冷啟動也不會閃現「未連結」結論。
- **介面語言固定繁體中文**：開發語言鎖 `zh-Hant`，並注入 `Locale(zh_Hant_TW)`，系統元件（滾輪、警示按鈕）不會退回英文；配色鎖淺色主題。
- **註冊改為導向官方網站**：App 內不做註冊表單、不注入任何腳本到政府身分驗證頁面。

### Removed

- **Face ID／Touch ID 開啟鎖與敏感動作再驗證**：移除 `BiometricGate` 與 `SensitiveAuthCoordinator`，同時移除 `NSFaceIDUsageDescription`。本版不再要求生物辨識權限；個資的保護改為單純依靠 iOS Keychain（`WhenUnlockedThisDeviceOnly`，裝置解鎖時才可讀）與「立即清除本機資料」。
- **以 HealthKit 數據產生上傳圖卡的功能**：不再由 App 合成任何要上傳的圖片。上傳一律由使用者自己從相簿挑選截圖，健康數據因此完全不離開裝置。
- **獨立的「設定」頁與「資安中心」子頁**：內容併入「我的資料」。

### Security

- **無自建後端**：本 App 沒有任何自建伺服器，開發者不接收、不儲存個資，也看不到任何身分或健康資料。唯一例外是使用者主動開啟「傳送匿名使用統計」之後，開發者可在 Firebase 主控台看到匿名的操作事件與當機報告（見下一條）。
- **唯一的第三方相依：firebase-ios-sdk 12.18.0**（Analytics + Crashlytics）。SPM 會解析 **13 個套件**，但**實際連進 App 二進位的只有 6 個**：`firebase-ios-sdk`、`GoogleAppMeasurement`、`GoogleDataTransport`、`GoogleUtilities`、`nanopb`、`promises`。其餘仍只用 Foundation / SwiftUI / HealthKit。
- **選 `FirebaseAnalyticsCore` 而非 `FirebaseAnalytics`**：底層為 `GoogleAppMeasurementCore`，**結構上不含 IDFA 收集能力**。Release 二進位已驗證未連結 `AdSupport`、`AppTrackingTransparency`、`AdServices`，因此不會出現 ATT 追蹤提示，`PrivacyInfo.xcprivacy` 的 `NSPrivacyTracking` 為 `false`、追蹤網域清單為空。
- **遙測預設關閉（opt-in）**：理由是 `FirebaseApp.configure()` 一執行就會產生 app instance ID 並送出 `first_open`——預設開的話，使用者在看到開關之前資料就已經送出去了。
- **遙測只有一個出口 `Telemetry.swift`**：其他檔案禁止 `import FirebaseAnalytics` / `FirebaseCrashlytics`。事件名、參數值與使用者屬性全是封閉列舉（自由字串在編譯期就送不出去），送出前再過四道閘門——未初始化、示範模式、使用者關閉、參數命中 `Redact` 敏感樣式（最後一道在 DEBUG build 直接 `assertionFailure`）。非致命錯誤只取 `domain`／`code`，訊息先過 `Redact.scrub` 再重新組一個乾淨的 `NSError`，不把原始 `userInfo` 交給 Crashlytics。
- **個資與健康資料一律不進遙測**：身分證號、出生日期、手機號碼的任何形式（原文、雜湊、截斷、拼接）都不送；HealthKit 衍生值也全部不送，**連「今日是否達標」這種由步數推導的布林值都不送**（Apple 禁止把健康資料分享給第三方）。唯一沾到健康的是 `health_auth_granted`——只說明使用者有沒有授權讀步數，不含任何數值。
- **新增 `PrivacyInfo.xcprivacy`**：宣告 `NSPrivacyTracking = false`、無追蹤網域、UserDefaults 使用理由 `CA92.1`，以及 CrashData／OtherDiagnosticData／ProductInteraction 三類資料（皆 not linked、not tracking）。
- **`GoogleService-Info.plist` 不進版控**：本 repo 公開，真檔一律排除，只附 `.template`。真檔不存在時 `Telemetry.configure()` 直接跳過初始化，遙測全程 no-op 且不 crash，clone 下來就能 build。
- **網域白名單**：`URLSessionHTTPClient` 只允許連線 `500.gov.tw`（含子網域，並擋 suffix 偽冒），其餘一律拋出 `blockedEgress`。**界線**：這個白名單管的是 App 自己發出的 HTTP 請求；Firebase SDK 走它自己的 `URLSession`，不受白名單管轄——使用者開啟遙測後，SDK 會另外連往 `app-analytics-services.com`、`firebaseinstallations.googleapis.com`、`firebase-settings.crashlytics.com`、`crashlyticsreports-pa.googleapis.com`、`firebaselogging.googleapis.com`。
- **ATS 強制 HTTPS**：`NSAllowsArbitraryLoads=false`，`500.gov.tw` 要求 TLS 1.2 以上與 forward secrecy，不開放任何明文例外。
- **修正官網 http 降級 redirect**：官網 302 的 `Location` 為 `http://`，client 一律正規化回 `https://` 再送，避免 Secure cookie 遺失與明文傳輸。
- **個資只存 iOS Keychain**：`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不同步 iCloud、不隨備份轉移；絕不寫入 `UserDefaults`、plist 或明文檔案。
- **Cookie 存在 App 沙盒容器、不外流**：`LBSCookie` / `JSESSIONID` 由 `URLSessionHTTPClient`（`persistCookies: true`）保存以維持登入狀態，僅限本 App 容器可讀；登出與「立即清除本機資料」都會呼叫 `resetSession()` 清空。cookie 的 domain scope 為 `500.gov.tw`，不會被送往其他網域。
- **統一日誌出口 `SecureLog` + `Redact`**：身分證、生日、手機、Email、健保卡號、cookie、`_csrf`、OTP、presigned URL 一律遮罩；debug 層級只在 DEBUG build 輸出。
- **HealthKit 唯讀**：只要求 `stepCount`、`distanceWalkingRunning`、`appleExerciseTime` 的讀取權限，從不寫入，資料也不離開裝置——**包含不進遙測**，即使使用者開啟了匿名統計也一樣。
- **不繞過任何身分驗證**：戶役政、健保卡、簡訊 OTP 皆為真實驗證，App 設計上不提供繞過路徑，也不提供任何可竄改運動數據的入口。
- **`ITSAppUsesNonExemptEncryption=false`**：只使用系統 TLS，屬出口管制豁免。

[1.0.0]: https://github.com/megshao/sports-rewards-ios/releases/tag/v1.0.0

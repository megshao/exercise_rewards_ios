# Sports Rewards（揮汗有禮活動・非官方輔助工具）

協助參加台灣運動部「揮汗有禮・全民動起來」運動幣加碼活動的 iOS App：
一鍵登入官方「我的任務」、免重複輸入個資、連結 Apple 健康看今日步數是否達標。

> **這是非官方工具，與運動部及任何政府機關沒有隸屬、合作、贊助或授權關係。**
> 活動規則與最終權益一律以官方公告為準。

App Store 上架名稱為 **Sports Rewards**。活動名「揮汗有禮」只作為說明文字出現，
**不作為 App 名稱**——刻意不使用活動名，避免被誤認為官方 App。

- 隱私權政策：<https://megshao.github.io/sports-rewards-ios/privacy.html>
- 支援與常見問題：<https://megshao.github.io/sports-rewards-ios/support.html>

## 架構

- `Sources/SportsRewardsKit/`（Swift Package）：核心邏輯，可 headless `swift build` / `swift test`
  - `Networking/` `URLSessionHTTPClient`（網域白名單、修正官方站 http→https 降級 redirect、`resetSession()` 清 cookie）、`CsrfParser`
  - `Services/` `AuthService`（access→login，無 OTP）、`TasksService`、`TaskParser`
  - `Security/` `KeychainStore`、`SecureLog`、`Redact`
  - `Health/` `HealthReading` 協定、`GoalEvaluator`
- `App/`（SwiftUI，XcodeGen 產生 `.xcodeproj`）：UI、HealthKit 實作、送審示範模式（`DemoMode`）
  - 介面固定繁體中文：開發語言鎖 `zh-Hant`（`App/project.yml`）＋注入 `Locale(zh_Hant_TW)`，不隨裝置語系變動
  - 個資最小化：只收集登入必需的**身分證號／出生日期／手機**三欄；姓名、Email、健保卡卡號**一律不收集**（App 不做註冊，未註冊者導向外部 Safari 到官網自行註冊）
  - **不含任何生物辨識**：不用 `LocalAuthentication`，`Info.plist` 也沒有 `NSFaceIDUsageDescription`
  - `App/Sources/App/Telemetry.swift`：全 App 唯一的 Firebase Analytics／Crashlytics 出口，封閉列舉 + 六道閘門，預設關閉（詳見下方威脅模型的「遙測」列）
  - `App/Resources/PrivacyInfo.xcprivacy`：App 自己的隱私資訊清單——`NSPrivacyTracking = false`、無追蹤網域、UserDefaults 理由 `CA92.1`，以及 CrashData／OtherDiagnosticData／ProductInteraction 三類（皆 not linked、not tracking）
- `App/UITests/`：以示範模式走完全部畫面、產出 App Store 截圖的 UI 測試

### 建置

```sh
swift test                       # 核心單元測試，不需 Xcode 專案
./Scripts/bootstrap.sh           # 產生 Xcode 專案，並套用 App/Package.resolved 的相依鎖定
xcodebuild -project App/SportsRewards.xcodeproj -scheme SportsRewards \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -disableAutomaticPackageResolution build
```

為什麼要這樣建：`.xcodeproj` 由 XcodeGen 產生、不進版控，而 Xcode 把 SPM 的鎖定檔放在 `.xcodeproj` 裡面，
於是鎖定檔也跟著進不了版控。`bootstrap.sh` 把版控中的真本 `App/Package.resolved`（13 個套件全部鎖到 git commit）
複製回 Xcode 期望的位置；建置時加 `-disableAutomaticPackageResolution`，Xcode 才不會偷偷重新解析、改寫它。
兩步都做到，任何人建出來的相依組合就跟我們一樣。要升級相依版本時跑 `./Scripts/bootstrap.sh --resolve`，步驟寫在腳本檔頭。

產生上架截圖（輸出到 `docs/screenshots/raw/`）：

```sh
cd App && xcodebuild test -project SportsRewards.xcodeproj \
  -scheme SportsRewardsScreenshots \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

## 安全設計（威脅模型摘要）

| 面向 | 措施 |
|---|---|
| 個資外洩 | 身分證／出生日期／手機（只收這三欄）只存 iOS Keychain（`WhenUnlockedThisDeviceOnly`、不同步 iCloud、不備份轉移）；**開發者沒有任何自建後端**。這三欄與 HealthKit 資料**任何形式（原文、雜湊、截斷、拼接）都不進遙測**，開發者收不到也看不到。開發者唯一看得到的東西是：使用者主動開啟「傳送匿名使用統計」之後，Firebase 主控台上的匿名操作事件與當機報告（見下方「遙測」列） |
| Log 洩漏 | 全專案唯一 log 入口 `SecureLog`；敏感值一律先過 `Redact`；`debug` 僅 DEBUG build 輸出；禁 log cookie/CSRF/OTP/session。App 與 SportsRewardsKit 內無 `print` / `NSLog` / 直接 `os_log`（UI 截圖測試除外） |
| 網路面 | ATS 強制 https；`URLSessionHTTPClient` 白名單只允許 `500.gov.tw`（含子網域、擋 suffix spoof），其餘 throw `blockedEgress`。唯一刻意例外：檢視已上傳截圖時，`ScreenshotView` 以 `AsyncImage` 載入官方網站回傳的簽章圖片網址（網域由官方網站決定；cookie 的 domain scope 是 `500.gov.tw`，不會送到該 host）；cookie 存在 App 沙盒容器（受 iOS 檔案保護、不進 iCloud），**重新登入前**（`AuthService` 登入流程開頭）與「立即清除本機資料」時都會 `resetSession()` 清空。<br>**白名單的界線要講清楚**：它是 `URLSessionHTTPClient` 內的檢查，只管**本 App 自己發出的 HTTP 請求**；Firebase SDK 用它自己的 `URLSession`，**不受這個白名單管轄**。使用者開啟遙測後，SDK 會連往 `app-analytics-services.com`、`firebaseinstallations.googleapis.com`、`firebase-settings.crashlytics.com`、`crashlyticsreports-pa.googleapis.com`、`firebaselogging.googleapis.com`（以上為 Release 二進位內實際出現的網域）。ATS 對它們一樣強制 HTTPS。<br>**刻意不做 certificate pinning**（App 與 Firebase SDK 皆無）：pinning 擋掉的是想用 mitmproxy 自己檢查請求內容的使用者，跟本專案「你可以自己查」的立場相反；而在 ATS 已強制 TLS 1.2+／forward secrecy 的前提下，它多擋的只剩「使用者自己在裝置上安裝並信任的憑證」這一種情境 |
| 中間人／降級 | 官方站 302 Location 是 `http://`；client 一律正規化回 https 再送，避免掉 Secure cookie |
| 裝置遺失 | 防線是 **iOS 裝置本身的鎖屏**（密碼／Face ID／Touch ID）加上 Keychain 的 `WhenUnlockedThisDeviceOnly`：**裝置上鎖時連本 App 自己都讀不到**這些欄位，資料也不會同步 iCloud 或隨備份轉移。另在「我的資料 › 安全與隱私」提供「立即清除本機資料」可隨時永久刪除。<br>**不做 App 內生物辨識鎖**：登入所需三碼本來就是使用者本人記得、官方網站登入也只驗這三碼，App 內再擋一次不會改變裝置遺失時的實際暴露面（真正的界線是裝置鎖屏），只是重複擋自己人 |
| 健康資料 | HealthKit **唯讀**步數／距離／運動時間，**從不寫入、從不外傳**；只在畫面上顯示與本機判斷是否達標。上傳一律由使用者自己從相簿選圖，App **不以健康數據合成任何要上傳的圖片** |
| 資料誠信 | 不繞過戶役政／健保卡／簡訊 OTP 等真實驗證，也不提供任何可竄改運動數據的入口 |
| 供應鏈 | **唯一的第三方相依是 firebase-ios-sdk 12.18.0**（Analytics + Crashlytics）。SPM 為了解析相依關係會 checkout **13 個套件**，但**實際連進 App 二進位的只有 6 個**：`firebase-ios-sdk`、`GoogleAppMeasurement`、`GoogleDataTransport`、`GoogleUtilities`、`nanopb`、`promises`（其餘 7 個——`abseil-cpp-binary`、`app-check`、`google-ads-on-device-conversion-ios-sdk`、`grpc-binary`、`gtm-session-fetcher`、`interop-ios-for-google-sdks`、`leveldb`——只被解析、沒有被連結，可用 `SportsRewards.LinkFileList` 覆核）。<br>選的是 **`FirebaseAnalyticsCore`** 而不是 `FirebaseAnalytics`：底層是 `GoogleAppMeasurementCore`，**結構上不含 IDFA 收集能力**——這是連結期的保證，不是 Info.plist 旗標的保證。Release 二進位已用 `otool -l` 驗證**沒有連結 `AdSupport`、`AppTrackingTransparency`、`AdServices`**，因此不會、也無法出現 ATT 提示。<br>其餘仍為純 Foundation / SwiftUI / HealthKit；**不使用 LocalAuthentication、不使用 WebKit/WKWebView** |
| 遙測 | **預設關閉，使用者 opt-in**。`Info.plist` 四個旗標（`FIREBASE_ANALYTICS_COLLECTION_ENABLED`、`FirebaseCrashlyticsCollectionEnabled`、`GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED`、`GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS`）全為 `false`；使用者要自己去「我的資料 › 安全與隱私 › 傳送匿名使用統計」打開才會開始送。<br>**為什麼預設關**：`FirebaseApp.configure()` 一執行就會產生 app instance ID 並送出 `first_open`——而且即使兩個收集旗標都是 false，Firebase Installations 仍會連 `firebaseinstallations.googleapis.com` 要一組 installation ID。預設開的話，使用者在看到那個開關之前，資料就已經送出去了。<br>**所以界線放在「執行與否」而不是旗標**：`Telemetry.configure()` 在使用者尚未同意時直接 return，`FirebaseApp.configure()` 根本不會被呼叫；使用者打開開關那一刻才是整支 App 第一次執行 Firebase 的程式碼。代價是 Crashlytics 抓不到 opt-in 之前的當機，這就是 opt-in 的語意。反向也要講清楚：關掉開關只會關收集旗標、重置 instance ID、刪未送報告，SDK 在本次執行期間仍在記憶體裡，要回到「一行都不跑」得等下一次冷啟動。<br>全 App 唯一的遙測出口是 `App/Sources/App/Telemetry.swift`（其他檔案禁止 `import FirebaseAnalytics` / `FirebaseCrashlytics`）。事件名與參數值都來自**封閉列舉**：`AnalyticsValue` 的底層儲存是 `private`，唯一能產生字串參數的建構子 `code(_:)` 只收封閉列舉的 rawValue，所以自由字串**值**在編譯期就構造不出來；使用者屬性是一個空列舉，根本無法建構。<br>**型別擋到哪為止要講清楚**：參數的**鍵**、以及 Crashlytics 的 breadcrumb 仍然是字串，那兩處靠的是送出前的樣式掃描而不是編譯器。送出前共**六道閘門**：示範模式 → 截圖模式 → 使用者關閉 → 未初始化 → 參數命中 `Redact` 敏感樣式 → 整數超出 `allowedIntRange`（最後兩道在 DEBUG build 直接 `assertionFailure`）。<br>**個資與 HealthKit 資料完全不進遙測**：連「今日是否達標」這種由步數推導出來的布林值都不送，因為 Apple 禁止把健康資料分享給第三方。唯一沾到健康的是 `health_link_tap`——「按了連結 Apple 健康的按鈕」這個 UI 動作，按下當下 HealthKit 尚未被呼叫；**不送授權結果**（`health_link_result` 刻意不實作，理由見 `Telemetry.swift`），也**不設定任何 user property**。<br>`GoogleService-Info.plist` 不進版控（本 repo 公開），只附 `.template`；真檔不存在時 `Telemetry.configure()` 直接跳過初始化，全程 no-op 且不 crash |
| 可驗證性 | 開源不等於「商店版＝這份原始碼」，所以把**能驗到哪一層**寫清楚，不宣稱做不到的事。四層階梯在[隱私權政策第 8 節](https://megshao.github.io/sports-rewards-ios/privacy.html#verify)：(1) iOS「App 隱私權報告」看連去哪——開關關著時本 App 只該出現 `500.gov.tw`，以及看截圖時官方網站回傳的圖片儲存網域（實測為 `amazonaws.com`，供應商由官方網站決定），**出現任何 Google 網域即為違約，歡迎打臉**；(2) mitmproxy 看每筆請求內容，操作指南與異常判準在 [`docs/verify-network.md`](docs/verify-network.md)；(3) 讀原始碼＋用 `bootstrap.sh` 重現相同相依組合；(4) **必須信任的兩件事**：Apple（商店版經重簽章與 FairPlay 加密，任何人都無法從商店版算出對應原始碼的雜湊，所以本專案**不公布 ipa 的 SHA-256**——對 iOS 那是驗不到東西的）、Google（`GoogleAppMeasurement` 閉源；我們只能保證未 opt-in 前它不被啟動、連結的是不含 IDFA 能力的 Core 版、連去的網域看得到） |

## 示範模式

登入需要真實身分證號與手機號碼，App Store 審查員拿不到，因此內建**完全揭露**的示範模式：
在登入表單輸入示範三碼即進入全 mock 環境，**不發出任何網路請求**（遙測也一併關閉：示範模式是 `Telemetry` 唯一沒有 bypass 的閘門，且 SDK 層的收集開關也會被關掉），個資只在記憶體、
不寫 Keychain，畫面頂端常駐「示範模式」橫幅。三碼寫在 `App/Sources/App/DemoMode.swift`，
並如實填寫於 App Store Connect 的示範帳號欄位。

## 授權

MIT，見 [`LICENSE`](LICENSE)。變更紀錄見 [`CHANGELOG.md`](CHANGELOG.md)。

問題回報：<https://github.com/megshao/sports-rewards-ios/issues>

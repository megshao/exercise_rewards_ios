# Sports Rewards（揮汗有禮活動・非官方輔助工具）

App Store 上架名稱為 **Sports Rewards**。活動名「揮汗有禮」只作為說明文字出現，
**不作為 App 名稱**（理由見 `docs/app-review-risk.md` 風險 #5：直接以官方活動名命名會踩
guideline 4.1(b) impersonation 與 5.2.1）。

加速參加台灣運動部「揮汗有禮・全民動起來」運動幣加碼活動的 iOS App：
一鍵登入官方「我的任務」、免重複輸入個資、串接 Apple 健康讀步數自動產生上傳圖卡。
**這是非官方工具，與運動部無關。**

## 架構
- `SportsRewardsKit/`（Swift Package）：核心邏輯，可 headless `swift build` / `swift test`
  - `Networking/` `URLSessionHTTPClient`（網域白名單、修正官方站 http→https 降級 redirect、cookie jar 登出即重置）、`CsrfParser`
  - `Services/` `AuthService`（access→login，無 OTP）、`TasksService`、`TaskParser`
  - `Security/` `KeychainStore`、`SecureLog`、`Redact`
  - `Health/` `HealthReading` 協定、`GoalEvaluator`
- `App/`（SwiftUI，XcodeGen 產生 `.xcodeproj`）：UI、HealthKit 實作、送審示範模式（`DemoMode`）
  - 介面固定繁體中文：開發語言鎖 `zh-Hant`（`App/project.yml`）＋注入 `Locale(zh_Hant_TW)`，不隨裝置語系變動
  - 「我的資料」頁同時承載安全與隱私設定（無獨立「資安中心」子頁）
  - 個資最小化：只收集登入必需的**身分證號／出生日期／手機**三欄；姓名、Email、健保卡卡號**一律不收集**（App 不做註冊，未註冊者導向外部 Safari 到官網自行註冊）
  - **v1.0 不含任何生物辨識**：不用 `LocalAuthentication`，`Info.plist` 也沒有 `NSFaceIDUsageDescription`

### 建置
```
swift test                       # 核心 72 tests
cd App && xcodegen generate
xcodebuild -scheme SportsRewards -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## 安全設計（威脅模型摘要）
| 面向 | 措施 |
|---|---|
| 個資外洩 | 身分證/出生日期/手機（v1.0 只收這三欄）只存 iOS Keychain（`WhenUnlockedThisDeviceOnly`、不同步 iCloud、不備份轉移）；**無任何雲端後端** |
| Log 洩漏 | 全專案唯一 log 入口 `SecureLog`；敏感值一律先過 `Redact`；`debug` 僅 DEBUG build 輸出；禁 log cookie/CSRF/OTP/session。全 repo 無 `print` / `NSLog` / 直接 `os_log` |
| 網路面 | ATS 強制 https；`URLSessionHTTPClient` 白名單只允許 `500.gov.tw`（含子網域、擋 suffix spoof），其餘 throw `blockedEgress`；cookie 存在 App 沙盒容器（受 iOS 檔案保護、不進 iCloud），登出 `resetSession()` 一併清空 cookie/cache |
| 中間人/降級 | 官方站 302 Location 是 `http://`；client 一律正規化回 https 再送，避免掉 Secure cookie |
| 裝置遺失 | 防線是 **iOS 裝置本身的鎖屏**（密碼／Face ID／Touch ID）加上 Keychain 的 `WhenUnlockedThisDeviceOnly`：**裝置上鎖時連本 App 自己都讀不到**這些欄位，資料也不會同步 iCloud 或隨備份轉移到別的裝置。另在「我的資料 › 安全與隱私」提供「立即清除本機資料」可隨時永久刪除。<br>**v1.0 已移除 App 內的 Face ID／Touch ID 解鎖與敏感動作再驗證**：登入所需的三碼本來就是使用者本人記得、且官方網站登入也只驗這三碼的資料，App 內再擋一次不會改變裝置遺失時的實際暴露面（真正的界線是裝置鎖屏），只是重複擋自己人 |
| 資料誠信 | 上傳圖卡只呈現真實 HealthKit 數據、無可竄改輸入、標「數據未經修改」；不繞過戶役政/健保卡/OTP 等真驗證 |
| 供應鏈 | 零第三方相依，純 Foundation / SwiftUI / HealthKit；**不使用 LocalAuthentication、不使用 WebKit/WKWebView、無任何 analytics 或 crash SDK** |

## 授權
MIT，見 `LICENSE`。詳細規格見 `docs/PRD.md`，任務拆解見 `docs/TASKS.md`。

# 揮汗有禮 App（非官方）

加速參加台灣運動部「揮汗有禮・全民動起來」運動幣加碼活動的 iOS App：
一鍵登入官方「我的任務」、免重複輸入個資、串接 Apple 健康讀步數自動產生上傳圖卡。
**這是非官方工具，與運動部無關。**

## 架構
- `SportsRewardsKit/`（Swift Package）：核心邏輯，可 headless `swift build` / `swift test`
  - `Networking/` `URLSessionHTTPClient`（網域白名單、修正官方站 http→https 降級 redirect、記憶體 cookie）、`CsrfParser`
  - `Services/` `AuthService`（access→login，無 OTP）、`TasksService`、`TaskParser`
  - `Security/` `KeychainStore`、`SecureLog`、`Redact`
  - `Health/` `HealthReading` 協定、`GoalEvaluator`
- `App/`（SwiftUI，XcodeGen 產生 `.xcodeproj`）：UI、HealthKit 實作、FaceID gate

### 建置
```
swift test                       # 核心 40 tests
cd App && xcodegen generate
xcodebuild -scheme Huihan -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## 安全設計（威脅模型摘要）
| 面向 | 措施 |
|---|---|
| 個資外洩 | 姓名/身分證/生日/手機/email/健保卡只存 iOS Keychain（`WhenUnlockedThisDeviceOnly`、不同步 iCloud、不備份轉移）；**無任何雲端後端** |
| Log 洩漏 | 全專案唯一 log 入口 `SecureLog`；敏感值一律先過 `Redact`；`debug` 僅 DEBUG build 輸出；禁 log cookie/CSRF/OTP/session |
| 網路面 | ATS 強制 https；`URLSessionHTTPClient` 白名單只允許 `500.gov.tw`（含子網域、擋 suffix spoof），其餘 throw `blockedEgress`；cookie 記憶體型、登出即清 |
| 中間人/降級 | 官方站 302 Location 是 `http://`；client 一律正規化回 https 再送，避免掉 Secure cookie |
| 裝置遺失 | 開啟 App 與顯示敏感欄位需 Face ID / Touch ID（`BiometricGate`，可設定開關） |
| 資料誠信 | 上傳圖卡只呈現真實 HealthKit 數據、無可竄改輸入、標「數據未經修改」；不繞過戶役政/健保卡/OTP 等真驗證 |
| 供應鏈 | 零第三方相依，純 Foundation / SwiftUI / HealthKit / LocalAuthentication |

## 授權
MIT，見 `LICENSE`。詳細規格見 `docs/PRD.md`，任務拆解見 `docs/TASKS.md`。

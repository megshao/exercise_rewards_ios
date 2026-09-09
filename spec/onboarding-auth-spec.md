# Onboarding 與 敏感動作驗證 規格

> **狀態（1.0 送審版）**：A 節已依 1.0 實作改寫。
> **B／C／D 節整段不再適用**——1.0 已移除生物辨識鎖與敏感動作再驗證，
> 兩個對應檔案（`App/Sources/Security/BiometricLock.swift`、`SensitiveAuth.swift`）已刪除，
> `NSFaceIDUsageDescription` 也一併移除。該三節保留為**歷史決策紀錄**，不得再當作實作依據。

## A. 首次啟動 Onboarding（強制）— 1.0 實作
1. 一開 App 若本機無個資 → 進 Onboarding，**強制填 3 欄位**：身分證字號、生日、手機號碼。
   - 個資最小化：姓名、email、健保卡卡號**不收集**（那三欄只有註冊才需要，而 1.0 不做註冊）。
2. 送出 → `AuthServicing.login`（內部即 `POST /access`(idNo) 分流 + login）：
   - `.success` → 存 Profile 到 Keychain → 進主畫面。
   - `.invalidCredentials` → 停在表單，提示「身分證／生日／手機有誤」。
   - `.notRegistered` → **App 不做註冊**：顯示提示＋「前往官網註冊」，用外部 Safari 開
     `https://500.gov.tw/registrant/access`；App 內不實作任何註冊步驟、不碰健保卡。
3. 驗證成功即直接進主畫面。**沒有任何生物辨識詢問或開關**——App 不使用 `LocalAuthentication`。
4. 示範模式：輸入哨兵三碼（`A000000000` / `1990-01-01` / `0900000000`）即進入送審示範模式，
   全服務換 Mock、個資只留記憶體、頂端常駐橫幅（見 `App/Sources/App/DemoMode.swift`）。

### A'. 裝置遺失的防線（取代原生物辨識設計）
- iOS 裝置本身的鎖屏（密碼／Face ID／Touch ID）是唯一且真正的界線。
- Keychain 屬性 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`：**裝置上鎖時連本 App 都讀不到**，
  且不同步 iCloud、不隨備份轉移到其他裝置。
- 「我的資料 › 安全與隱私 › 立即清除本機資料」可隨時永久刪除本機個資。

## B.〔歷史紀錄・1.0 已移除〕Face ID 守門點（敏感動作前重新驗證）

> ⛔ **本節（含 C、D 節）描述的功能已於 1.0 全數移除，不再是本 App 的行為。**
> 移除理由：登入三碼是使用者本人記得、且官方網站登入本身也只驗這三碼的資料，
> App 內再擋一次不改變裝置遺失時的實際暴露面（真正的界線是裝置鎖屏 + Keychain
> `WhenUnlockedThisDeviceOnly`），而多帶一個 `NSFaceIDUsageDescription` 只會增加送審要解釋的權限面。
> 以下原文保留作決策軌跡。

原本規劃需在以下三個點做「敏感動作驗證」：
1. **進入個資設定頁面**（開 ProfileView 前）
2. **儲存個資**（Save 前）
3. **兌換 redeem**（進 RedeemView / 送出兌換前）

## C.〔歷史紀錄・1.0 已移除〕驗證方式與 fallback
- 若已啟用 Face ID 且裝置可用 → LocalAuthentication `.deviceOwnerAuthentication`（可退裝置密碼）。
- **若未設定 Face ID** → fallback：要使用者輸入 **email ＋ 手機號碼**，兩者都與本機儲存的 Profile **完全 match** 才給過。
  - email 比對可 trim + 忽略大小寫；手機去除空白後完全相等。兩者皆須相符。
- 驗證通過才執行該敏感動作；取消/失敗則不執行、留在原地。

## D.〔歷史紀錄・1.0 已移除〕實作備註
- 抽一個可重用的 `SensitiveAuth`（或 AuthGate）：`func authorize(reason:) async -> Bool`，內部依 biometricLockEnabled + 可用性選 Face ID 或 email+phone fallback sheet（比對 ProfileStoring 讀出的 Profile）。
- 三個守門點都呼叫它。
- 這與「開 App 解鎖」的 BiometricGate 不同層級：BiometricGate 只在使用者於 onboarding 後選擇啟用時，於冷啟動解鎖；本節是「動作級」再驗證。
- **絕不 log** email/手機/otp/個資。（此條**仍然有效**，且與生物辨識無關：全專案唯一 log 入口為 `SecureLog`＋`Redact`。）

## E. UI 一致性
- 主畫面步數卡與本週任務卡等所有卡片統一滿版寬（maxWidth: .infinity），消除長短不一。
- 生日欄位在 Onboarding 與「我的資料」共用同一元件（`BirthDateField` → `BirthDatePickerSheet`）：年／月／日三欄滾輪、民國／西元可切換（預設民國）、底部雙年份確認，不用系統日曆式 DatePicker；對外仍存 ISO `yyyy-MM-dd`（詳見 PRD §5.2）。
- 介面文案一律自備繁體中文、不吃裝置語系（開發語言鎖 `zh-Hant` ＋ `Locale(zh_Hant_TW)`）。

## F.〔延後至 Phase 2〕註冊全流程實測（R-register）

> 1.0 不做 App 內註冊（見 A 節第 2 點），本節為 Phase 2 的前置實測計畫。
使用者稍後提供「未註冊、且本人同意」的測試個資（姓名/身分證/生日/手機/email/健保卡）。
屆時比照 redeem 逐步實測並記錄：
- POST /register (name,idNo,birthDate,phone,email,agree=true) → 觀察導向 /register/nhi-verify
- /register/nhi-verify：抓健保卡欄位名、戶役政生日驗證、送出後回應/導向
- /register/otp：抓 OTP 發送/驗證/resend 欄位與錯誤格式
- 完成後補進 ExerciseRewardsKit 的註冊 service 與 Onboarding 註冊分支。
注意：會實際綁定該身分證＋門號（1門號1身分證），須本人同意；記錄勿寫入真實個資明碼。

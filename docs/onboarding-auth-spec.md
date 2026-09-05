# Onboarding 與 敏感動作驗證 規格（使用者確認版）

## A. 首次啟動 Onboarding（強制）
1. 一開 App 若本機無完整個資 → 進 Onboarding，**強制填 6 欄位**：姓名、身分證字號、生日、手機號碼、email、健保卡卡號。
2. 送出 → `POST /access`(idNo) 分流：
   - 已註冊 → 走**登入**（idNo+birthDate+phone 三碼）→ 成功 → 進主畫面。
   - 未註冊 → 走**註冊**：`POST /register`(name,idNo,birthDate,phone,email,agree=true) → `/register/nhi-verify`(健保卡) → `/register/otp`(簡訊) → 完成 → 進主畫面。
     - ⚠️ nhi-verify / otp 兩步欄位未實測（需未註冊身分才能抓），先搭到 /register，後兩步標 TODO。
3. 驗證成功後 → **詢問是否啟用 Face ID**（可略過）。略過就直接進主畫面，設定頁可再開。
4. **Onboarding 完成前完全不碰 Face ID**（預設 `biometricLockEnabled=false`，不在第一次開 App 就要權限）。

## B. Face ID 守門點（敏感動作前重新驗證）
需在以下三個點做「敏感動作驗證」：
1. **進入個資設定頁面**（開 ProfileView 前）
2. **儲存個資**（Save 前）
3. **兌換 redeem**（進 RedeemView / 送出兌換前）

## C. 驗證方式與 fallback
- 若已啟用 Face ID 且裝置可用 → LocalAuthentication `.deviceOwnerAuthentication`（可退裝置密碼）。
- **若未設定 Face ID** → fallback：要使用者輸入 **email ＋ 手機號碼**，兩者都與本機儲存的 Profile **完全 match** 才給過。
  - email 比對可 trim + 忽略大小寫；手機去除空白後完全相等。兩者皆須相符。
- 驗證通過才執行該敏感動作；取消/失敗則不執行、留在原地。

## D. 實作備註
- 抽一個可重用的 `SensitiveAuth`（或 AuthGate）：`func authorize(reason:) async -> Bool`，內部依 biometricLockEnabled + 可用性選 Face ID 或 email+phone fallback sheet（比對 ProfileStoring 讀出的 Profile）。
- 三個守門點都呼叫它。
- 這與「開 App 解鎖」的 BiometricGate 不同層級：BiometricGate 只在使用者於 onboarding 後選擇啟用時，於冷啟動解鎖；本節是「動作級」再驗證。
- **絕不 log** email/手機/otp/個資。

## E. UI 一致性
- 主畫面步數卡與本週任務卡等所有卡片統一滿版寬（maxWidth: .infinity），消除長短不一。

## F. 待辦：註冊全流程實測（R-register）
使用者稍後提供「未註冊、且本人同意」的測試個資（姓名/身分證/生日/手機/email/健保卡）。
屆時比照 redeem 逐步實測並記錄：
- POST /register (name,idNo,birthDate,phone,email,agree=true) → 觀察導向 /register/nhi-verify
- /register/nhi-verify：抓健保卡欄位名、戶役政生日驗證、送出後回應/導向
- /register/otp：抓 OTP 發送/驗證/resend 欄位與錯誤格式
- 完成後補進 SportsRewardsKit 的註冊 service 與 Onboarding 註冊分支。
注意：會實際綁定該身分證＋門號（1門號1身分證），須本人同意；記錄勿寫入真實個資明碼。

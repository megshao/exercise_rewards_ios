# Sports Rewards App — 實作 Task 拆解

命名：上架名 **Sports Rewards**；「揮汗有禮」只作為活動說明用語，不作為 App 名稱（見 `docs/app-review-risk.md`）。
技術：iOS 原生 SwiftUI + URLSession。
硬約束：個資只存 Keychain（`WhenUnlockedThisDeviceOnly`）、不上雲、不寫 log、**App 自己只連 500.gov.tw**、將開源。

> **1.0 硬約束變更（一）**：原本列在硬約束裡的「FaceID 鎖」已於 1.0 移除。裝置遺失的防線改為
> iOS 裝置鎖屏 + Keychain `WhenUnlockedThisDeviceOnly`（裝置上鎖時連 App 自己都讀不到）
> 加上「立即清除本機資料」。詳細理由見 `docs/PRD.md` §8.1 決策紀錄。
>
> **1.0 硬約束變更（二）：「禁用第三方 analytics/crash SDK」已於 1.0 變更（2026-09-06）。**
> 原本的硬約束是「不上雲、不寫 log、只連 500.gov.tw」，並在 `docs/PRD.md` §8.2 明訂禁用會外傳個資的
> 第三方 analytics / crash SDK。1.0 加入了 **firebase-ios-sdk 12.18.0**（Analytics + Crashlytics）。
>
> - **為什麼改**：本 App 靠刮官網 HTML 運作，官網一改版功能就整組失效；沒有遙測時，我們只能等使用者來信
>   才知道解析器壞了。需要一條「官網改版時最早的警報」。量測設計見 `docs/analytics-plan.md`。
> - **變更後的六條前提**（缺一不可）：預設關閉由使用者 opt-in／個資零外傳／HealthKit 資料與其推導結論零外傳／
>   單一出口 + 封閉列舉／四道閘門（未初始化・示範模式・使用者關閉・敏感樣式）／不引入廣告識別能力。
> - **代價**：「零第三方相依」的說法作廢，隱私標籤四格從 Not Collected 改為 Collected，
>   5.1.3(i) 從「不必解釋」變成「必須主動解釋」。
> - **沒有改變的部分**：個資與健康資料仍然完全不外傳，隱私標籤的 Health / Fitness 兩格仍是 Not Collected。
> - 完整決策紀錄與代價清單見 `docs/PRD.md` §8.2；對外文案的對應改寫見 `README.md`、`CHANGELOG.md`、
>   `site/privacy.html` §5、`docs/release/privacy-labels.md`、`docs/release/review-notes.md` §5b。

---

## Phase 0 — 專案骨架與資安地基（先做，之後每刀都依賴）
- [x] 0.1 建立 Xcode 專案（SwiftUI、iOS 目標版本、Bundle ID）、Git init、.gitignore
- [x] 0.2 開源基礎：LICENSE(MIT)、README（含威脅模型摘要）、無硬編碼密鑰
- [x] 0.3 設計系統：白底亮橘 token（色/字/圓角/陰影）做成 Theme，Baloo 2 + Noto Sans TC 字體
- [x] 0.4 **KeychainStore**：個資 6 欄位讀寫，屬性 WhenUnlockedThisDeviceOnly、不同步 iCloud
- [x] 0.5 **SecureLog**：全專案統一 log 入口，強制遮罩身分證/生日/手機/email/健保卡/cookie/OTP；release 關閉敏感層級
- [x] 0.6 **ATS/網域白名單**：Info.plist 只允許 https 到 500.gov.tw；封鎖其他 egress
- [~] 0.7 ~~FaceID/LocalAuthentication 解鎖 gate（App 啟動 + 敏感欄位）~~ — **曾實作，已於 1.0 移除**
  - 原產出 `App/Sources/Security/BiometricLock.swift`（`BiometricGate`）與 `SensitiveAuth.swift`
    （`SensitiveAuthCoordinator` + email/手機 fallback），連同 `NSFaceIDUsageDescription` 一併刪除
    （commit `refactor(app): drop biometric gate and sensitive-action re-auth`）。
  - 移除理由與替代防線見 `docs/PRD.md` §8.1；`docs/onboarding-auth-spec.md` B/C/D 節已標為歷史紀錄。

## Phase 1 — 一鍵登入（MVP 第一刀）
- [x] 1.1 **HttpClient**：URLSession + HTTPCookieStorage（記憶體、登出即清）、強制 http→https 修正、統一錯誤處理
- [x] 1.2 **CsrfParser**：GET 頁面刮 `_csrf`（先用字串/正規式，必要時輕量 HTML parse）
- [x] 1.3 **SessionBootstrap**：處理 HiNetCDN LBSCookie（`?_cookie_check=1`）首次握手
- [x] 1.4 **AuthService.login**：`POST /access(idNo)` → GET `/login` → `POST /login(idNo,birthDate,phone)` → 判斷 302 `/member/tasks` 成功；區分「未註冊(導 /register)」與「三碼不符」錯誤
- [x] 1.5 Profile 設定畫面「我的資料」（存/讀 Keychain、遮罩顯示，點擊欄位即展開明文；**1.0 起不需 FaceID**）
  - [x] 1.5.4 個資最小化：只收登入必需的身分證／生日／手機三欄；姓名／Email／健保卡卡號不再收集（`Profile` model 保留欄位但恆為空字串）
  - [x] 1.5.1 出生日期改自製「年／月／日」三欄滾輪 sheet（民國/西元切換、預設民國、雙年份確認、換月自動夾日），不用系統日曆式 DatePicker；對外仍存 ISO `yyyy-MM-dd`。Onboarding 共用同一元件
  - [x] 1.5.2 App 開發語言鎖 `zh-Hant`（`project.yml` developmentLanguage、CFBundleDevelopmentRegion/CFBundleLocalizations）＋注入 `Locale(zh_Hant_TW)`，介面文案不吃裝置語系
  - [~] 1.5.3 移除「設定 — 資安中心」子頁，~~Face ID 開關~~／本機資料說明／立即清除（含確認 alert、清除後回 Onboarding）與版本聲明併入本頁「安全與隱私」區塊；頁首隱私聲明改為三點明列
    - **1.0 修正**：其中的「Face ID 開關」隨生物辨識鎖一併移除，本區塊現在只有本機資料說明、立即清除與版本／非官方聲明。
- [x] 1.6 首頁 Home（一鍵登入 CTA、登入中/失敗狀態、登入態保存）
- [x] 1.7 登出：`POST /logout` + 清 cookie/session

## Phase 2 — 任務儀表板（MVP 第二刀）
- [x] 2.1 **TasksService.fetchTasks**：GET `/member/tasks`，解析 14 期（期數/日期/UUID/狀態/倒數/上傳・審核時間）
- [x] 2.2 狀態機 model：NOT_STARTED / OPEN(可上傳) / 待審核 / REDEEMABLE / 已兌換
- [x] 2.3 任務儀表板畫面（本週置頂卡、狀態徽章、倒數、下拉刷新）
- [x] 2.4 看截圖：GET `/member/screenshot/{uuid}` → 顯示 S3 圖

## Phase 3 — HealthKit 讀步數 + 產生上傳圖卡（第三刀）
- [x] 3.1 HealthKit 授權（唯讀 stepCount / distanceWalkingRunning / appleExerciseTime）
- [x] 3.2 達標判定（對應任務辦法：單日 8000 步 或 健走 30 分 或 跑步 5km）
- [x] 3.3 健康數據畫面（步數環、達標徽章、指標卡）
  - [x] 3.3.1 首頁步數環未連結狀態：`HealthLinkState { checking, linked, notLinked }` 三態（避免冷啟動閃現「未連結」）；未連結顯示淺灰虛線環＋灰色步行圖示＋「未連結」（opacity 0.55）＋「前往連結 ›」，並移除原本的示意假數字
- [x] 3.4 **圖卡產生器**：忠實呈現真實 HealthKit 數據（日期/步數/距離/時間），標「資料來源 Apple 健康・未經修改」；渲染成可上傳圖片

## Phase 4 — 上傳 + 兌換（第四刀，含未決點）
- [x] 4.1 ✅ 已實測：`/member/upload` multipart file 欄位名 = `screenshot`（PRD R1，見 docs/redeem-flow-capture.md）
- [x] 4.2 UploadService：multipart POST `/member/upload`（圖卡或相簿選圖）
- [x] 4.3 兌換畫面（商店清單）+ RedeemService `POST /member/redeem/{uuid}(vendorId,item)`
- [x] 4.4 ⚠️ 待補：兌換後 OTP 端點與券碼結構（PRD R2，會消耗真實次數，需你同意再實測）
- [x] 4.5 券夾（QR/條碼出示）

## Phase 5 — 首次註冊（**1.0 不做**，延後至 Phase 2）
- [ ] 5.1 註冊表單 `POST /register` → 5.2 `/register/nhi-verify`(健保卡) → 5.3 `/register/otp`(簡訊，簡訊自動帶入)
  - **1.0 決策**：App 內完全不實作註冊。`/access` 回報未註冊時，改以外部 Safari 開官網
    `https://500.gov.tw/registrant/access` 讓使用者自行完成，App 不碰健保卡／戶役政／OTP。

## 橫向 / 收尾
- [ ] 推播提醒（每週上傳期開始 / 截止前 N 小時）
- [ ] 無障礙 AA（動態字級、對比、VoiceOver）
- [x] 單元測試（AuthService/TasksService/解析器/KeychainStore）— `swift test` 72 tests 全綠
- [x] 資安自審（無 log 洩漏、無雲端呼叫、依賴審查）— 見送審自審報告；未結項目：`clearLocalData()` 未清 cookie、示範模式的 `MockTasksService.screenshotImageURL` 仍指向 `picsum.photos`

## 1.0 送審相關
- [x] 移除生物辨識鎖與敏感動作再驗證（0.7 / 1.5.3 的一部分，見上）
- [x] 送審示範模式 `DemoMode`（哨兵三碼進入，全 Mock 服務、個資只在記憶體、常駐橫幅）
- [x] 上架名／簽章／zh-Hant 鎖定（`App/project.yml`）

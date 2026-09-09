# Exercise Rewards App — 實作 Task 拆解

命名：上架名 **Exercise Rewards**；「揮汗有禮」只作為活動說明用語，不作為 App 名稱（見 `spec/app-review-risk.md`）。
技術：iOS 原生 SwiftUI + URLSession。
硬約束：個資只存 Keychain（`WhenUnlockedThisDeviceOnly`）、不上雲、不寫 log、**App 自己只連 500.gov.tw**（1.2 起有一個唯讀例外，見下方變更（四））、將開源。

> **1.0 硬約束變更（一）**：原本列在硬約束裡的「FaceID 鎖」已於 1.0 移除。裝置遺失的防線改為
> iOS 裝置鎖屏 + Keychain `WhenUnlockedThisDeviceOnly`（裝置上鎖時連 App 自己都讀不到）
> 加上「立即登出並清除本機資料」（1.2 更名，舊名「立即清除本機資料」）。詳細理由見 `spec/PRD.md` §8.1 決策紀錄。
>
> **1.0 硬約束變更（二）：「禁用第三方 analytics/crash SDK」已於 1.0 變更（2026-09-06）。**
> 原本的硬約束是「不上雲、不寫 log、只連 500.gov.tw」，並在 `spec/PRD.md` §8.2 明訂禁用會外傳個資的
> 第三方 analytics / crash SDK。1.0 加入了 **firebase-ios-sdk 12.18.0**（Analytics + Crashlytics）。
>
> - **為什麼改**：本 App 靠刮官網 HTML 運作，官網一改版功能就整組失效；沒有遙測時，我們只能等使用者來信
>   才知道解析器壞了。需要一條「官網改版時最早的警報」。量測設計見 `spec/analytics-plan.md`。
> - **變更後的六條前提**（缺一不可）：初始化綁在免責聲明的主動同意之後（同意前 Firebase 一行程式碼都不執行）／
>   個資零外傳／不讀取任何健康資料（v1.1 起）／單一出口 + 封閉列舉／
>   六道閘門（示範模式・截圖模式・使用者關閉・未初始化・敏感樣式・整數值域）／不引入廣告識別能力。
> - **代價**：「零第三方相依」的說法作廢，隱私標籤四格從 Not Collected 改為 Collected，
>   5.1.3(i) 從「不必解釋」變成「必須主動解釋」。
>
> **1.0 硬約束變更（三）：遙測預設值改為「同意後預設開啟」（2026-09-06 二次修訂）。**
> 上面第一條原本寫的是「預設關閉由使用者 opt-in」。`Telemetry.defaultEnabled` 現在是 `true`。
>
> - **正確敘述**：首次啟動先擋一張必須主動勾選的免責聲明（`DisclaimerView`），畫面明寫會把匿名操作紀錄與當機報告送給
>   Google Firebase；按下「同意並開始使用」時 `DisclaimerConsent.record()` 才呼叫 `Telemetry.configure()`——
>   那是整支 App 第一次執行 Firebase 程式碼的時機。**同意之後預設開啟**，可隨時在「我的資料 › 安全與隱私」關掉。
> - **不得使用的措辭**：「預設關閉」「出廠是關的」「opt-in」「使用者自己打開才會送」。這些現在都是不實陳述。
> - **Info.plist 四個旗標仍為 `false`**，但意義變了：那是冷啟動預設值，由 `applyCollectionFlags` 在初始化後覆寫，
>   用來守住「還沒 `configure()` 就絕不收集」——不是「預設關閉」的證據。
> - **連帶失效的舊承諾**：「示範模式下對 Google 零連線」不再成立（免責聲明擋在 Onboarding 之前，
>   示範模式是在 Onboarding 才進入的），詳見 `spec/release/review-notes.md` §2／§5b 與 `spec/PRD.md` §8.2 決策紀錄。
> - 對外文案的對應改寫見 `README.md`、`CHANGELOG.md`、`docs/index.html`、`docs/privacy.html` §5／§8、`docs/support.html`、
>   `spec/release/privacy-labels.md`、`spec/release/review-notes.md`、`spec/release/app-store-metadata.md`、`spec/app-review-risk.md`。
> - **沒有改變的部分**：個資仍然完全不外傳，隱私標籤的 Health / Fitness 兩格仍是 Not Collected（v1.1 起理由更單純——App 根本不讀健康資料）。
> - 完整決策紀錄與代價清單見 `spec/PRD.md` §8.2；對外文案的對應改寫見 `README.md`、`CHANGELOG.md`、
>   `docs/privacy.html` §5、`spec/release/privacy-labels.md`、`spec/release/review-notes.md` §5b。
>
> **1.2 硬約束變更（四）：「App 自己只連 500.gov.tw」多了一個唯讀例外（2026-09-09）。**
> `VendorCatalogService` 會從 `https://megshao.github.io/exercise_rewards_ios/vendor-catalog.json`
> 下載一份公開的廠商品項目錄快照——**這是 App 自己發出的、離開 500.gov.tw 的請求**，不是 SDK 內部連線。
>
> - **為什麼需要**：已兌換的期別在官網已經沒有兌換頁，而品項頁連結只長在兌換頁上；在官網或別台手機兌換的期別
>   靠官網湊不出那個路徑（見 `spec/PRD.md` §5.8 的三層解析）。
> - **界線**：刻意**不加進** `URLSessionHTTPClient` 的主機白名單（那道白名單是防憑證外流的機制），
>   自己開 ephemeral、無 cookie、無憑證的 session；只下載零上傳；**只在補不到時才發**
>   （券夾的路徑解析每個 `WalletViewModel` 最多一次；品項頁內容備援在官網那一頁載入失敗後才發。兩個呼叫點共用 `VendorCatalogService` 的行程內快取，所以整個 App session 最多只抓一次——見 PRD §8.3）；
>   示範模式走 `EmptyVendorCatalogService`，一個請求都不發。
> - **正確敘述**：「App 自己的請求只連 500.gov.tw，唯一例外是一個唯讀、無 cookie、零上傳的公開備份檔」。
>   **不得**再寫成無條件的「只連 500.gov.tw」。
> - 完整規格與決策紀錄見 `spec/PRD.md` §8.3；對外文案見 `README.md`〈網路出口〉、`docs/privacy.html`。

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
  - 移除理由與替代防線見 `spec/PRD.md` §8.1；`spec/onboarding-auth-spec.md` B/C/D 節已標為歷史紀錄。

## Phase 1 — 一鍵登入（MVP 第一刀）
- [x] 1.1 **HttpClient**：URLSession + HTTPCookieStorage（記憶體、登出即清）、強制 http→https 修正、統一錯誤處理
- [x] 1.2 **CsrfParser**：GET 頁面刮 `_csrf`（先用字串/正規式，必要時輕量 HTML parse）
- [x] 1.3 **SessionBootstrap**：處理 HiNetCDN LBSCookie（`?_cookie_check=1`）首次握手
- [x] 1.4 **AuthService.login**：`POST /access(idNo)` → GET `/login` → `POST /login(idNo,birthDate,phone)` → 判斷 302 `/member/tasks` 成功；區分「未註冊(導 /register)」與「三碼不符」錯誤
- [x] 1.5 Profile 畫面「我的資料」（讀 Keychain、遮罩顯示；**1.0 起不需 FaceID**）
  - [x] 1.5.5 **1.2：這一頁改為唯讀**——三欄改用 `ProfileValueRow` 顯示，移除「儲存到本機」按鈕、`ProfileViewModel.save()`
    與儲存成功／失敗的 alert；遮罩與「點這裡顯示完整內容」的整頁切換保留，出生日期不遮罩。
    個資唯一的寫入點改為 Onboarding 的首次設定。理由與代價見 `spec/PRD.md` §5.2 決策紀錄。
  - [x] 1.5.4 個資最小化：只收登入必需的身分證／生日／手機三欄；姓名／Email／健保卡卡號不再收集（`Profile` model 保留欄位但恆為空字串）
  - [x] 1.5.1 出生日期改自製「年／月／日」三欄滾輪 sheet（民國/西元切換、預設民國、雙年份確認、換月自動夾日），不用系統日曆式 DatePicker；對外仍存 ISO `yyyy-MM-dd`。**1.2 起只有 Onboarding 在用**（「我的資料」唯讀後沒有輸入元件）；
    選完日期焦點自動移到「手機號碼」（在 sheet 的 `onDismiss` 才設，按「取消」不移動）
  - [x] 1.5.2 App 開發語言鎖 `zh-Hant`（`project.yml` developmentLanguage、CFBundleDevelopmentRegion/CFBundleLocalizations）＋注入 `Locale(zh_Hant_TW)`，介面文案不吃裝置語系
  - [~] 1.5.3 移除「設定 — 資安中心」子頁，~~Face ID 開關~~／本機資料說明／立即清除（含確認 alert、清除後回 Onboarding）與版本聲明併入本頁「安全與隱私」區塊；頁首隱私聲明改為三點明列
    - **1.0 修正**：其中的「Face ID 開關」隨生物辨識鎖一併移除。
    - **1.2 修正**：「安全與隱私」區塊現在是〔離開示範模式（僅示範模式）／本機資料說明／傳送匿名使用統計／原始碼〕四列；
      **清除／換帳號已從這張清單移出**，改名「立即登出並清除本機資料」並獨立成「換帳號」區塊（它是這一頁唯一會改變狀態的動作）。
      頁首隱私聲明也從三點擴充為六點（多了「為什麼不能修改」、剪貼簿、商品目錄備份檔）。見 `spec/PRD.md` §5.2／§5.9。
- [x] 1.6 首頁 Home（一鍵登入 CTA、登入中/失敗狀態、登入態保存）
- [x] 1.7 登出：`POST /logout` + 清 cookie/session

## Phase 2 — 任務儀表板（MVP 第二刀）
- [x] 2.1 **TasksService.fetchTasks**：GET `/member/tasks`，解析 14 期（期數/日期/UUID/狀態/倒數/上傳・審核時間）
- [x] 2.2 狀態機 model：NOT_STARTED / OPEN(可上傳) / 待審核 / REDEEMABLE / 已兌換
- [x] 2.3 任務儀表板畫面（本週置頂卡、狀態徽章、倒數、下拉刷新）
- [x] 2.4 看截圖：GET `/member/screenshot/{uuid}` → 顯示 S3 圖

## Phase 3 — HealthKit 讀步數 + 產生上傳圖卡（第三刀）

> ⚠️ **這一整個 Phase 的產出已於 v1.1 全部刪除**（連 entitlement 一起）。
> 保留勾選紀錄是為了說明這些檔案曾經存在、以及為什麼後來整批移除。
- [x] 3.1 HealthKit 授權（唯讀 stepCount / distanceWalkingRunning / appleExerciseTime）
- [x] 3.2 達標判定（對應任務辦法：單日 8000 步 或 健走 30 分 或 跑步 5km）
- [x] 3.3 健康數據畫面（步數環、達標徽章、指標卡）
  - [x] 3.3.1 首頁步數環未連結狀態：`HealthLinkState { checking, linked, notLinked }` 三態（避免冷啟動閃現「未連結」）；未連結顯示淺灰虛線環＋灰色步行圖示＋「未連結」（opacity 0.55）＋「前往連結 ›」，並移除原本的示意假數字
- [x] 3.4 **圖卡產生器**：忠實呈現真實 HealthKit 數據（日期/步數/距離/時間），標「資料來源 Apple 健康・未經修改」；渲染成可上傳圖片

## Phase 4 — 上傳 + 兌換（第四刀，含未決點）
- [x] 4.1 ✅ 已實測：`/member/upload` multipart file 欄位名 = `screenshot`（PRD R1，見 spec/redeem-flow-capture.md）
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
- [x] 資安自審（無 log 洩漏、無雲端呼叫、依賴審查）— 見送審自審報告
  - **已補**：`clearLocalData()` 現在會呼叫 `resetSession()` 清 cookie jar，並一併清 `VoucherUsage`／`VendorIntroStore`／遙測偏好／免責聲明同意紀錄（見 `spec/PRD.md` §5.9）。
  - **已補**：`MockTasksService.screenshotImageURL` 改讀 bundle 內的 `DemoScreenshot.png`，示範模式不再有任何對外請求。
  - **1.2 新增待審項**：`VendorCatalogService` 是白名單外唯一的 App 自身出口，需列入依賴／出口審查清單（見上方硬約束變更（四））。

## 1.2（尚未發行）
- [x] 「我的資料」改唯讀（1.5.5，見上）
- [x] 「立即登出並清除本機資料」更名 + 獨立成「換帳號」區塊（1.5.3 的 1.2 修正，見上）
- [x] 券夾：已兌換券卡「檢視券碼」→「顯示加碼券條碼結帳」；新增「查看可兌換品項」（擺在結帳鈕**上方**），開與兌換頁同一個 `VendorIntroView`
- [x] 券夾的兌換 sheet 補 `onDismiss` 重抓（否則從券夾兌換完那一期會一直停在「可兌換」）
- [x] 任務卡「檢視加碼券」改為只切換到券夾分頁（原本那個券碼 sheet 已移除）
- [x] 新增 `RootTab` / `TabRouter`：券碼頁看完條碼關閉後一律導回「我的券夾」分頁（只在條碼階段才切）
- [x] 新增 `VendorIntroStore`（`taskID → introPath`，算「本機資料」，清除與示範模式切換都要清）
- [x] 新增 `VendorCatalogService` 離線備份（白名單外唯一的 App 自身出口，見硬約束變更（四））
- [ ] `vendor-catalog.json` 的定期重抓／比對流程（快照會過期，見 `spec/PRD.md` §14 R8）

## 1.0 送審相關
- [x] 移除生物辨識鎖與敏感動作再驗證（0.7 / 1.5.3 的一部分，見上）
- [x] 送審示範模式 `DemoMode`（哨兵三碼進入，全 Mock 服務、個資只在記憶體、常駐橫幅）
- [x] 上架名／簽章／zh-Hant 鎖定（`App/project.yml`）

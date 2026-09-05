# 揮汗有禮 App — 實作 Task 拆解

命名：揮汗有禮（非官方工具）。技術：iOS 原生 SwiftUI + URLSession。
硬約束：個資只存 Keychain、不上雲、不寫 log、只連 500.gov.tw、FaceID 鎖、將開源。

---

## Phase 0 — 專案骨架與資安地基（先做，之後每刀都依賴）
- [x] 0.1 建立 Xcode 專案（SwiftUI、iOS 目標版本、Bundle ID）、Git init、.gitignore
- [x] 0.2 開源基礎：LICENSE(MIT)、README（含威脅模型摘要）、無硬編碼密鑰
- [x] 0.3 設計系統：白底亮橘 token（色/字/圓角/陰影）做成 Theme，Baloo 2 + Noto Sans TC 字體
- [x] 0.4 **KeychainStore**：個資 6 欄位讀寫，屬性 WhenUnlockedThisDeviceOnly、不同步 iCloud
- [x] 0.5 **SecureLog**：全專案統一 log 入口，強制遮罩身分證/生日/手機/email/健保卡/cookie/OTP；release 關閉敏感層級
- [x] 0.6 **ATS/網域白名單**：Info.plist 只允許 https 到 500.gov.tw；封鎖其他 egress
- [x] 0.7 FaceID/LocalAuthentication 解鎖 gate（App 啟動 + 敏感欄位）

## Phase 1 — 一鍵登入（MVP 第一刀）
- [x] 1.1 **HttpClient**：URLSession + HTTPCookieStorage（記憶體、登出即清）、強制 http→https 修正、統一錯誤處理
- [x] 1.2 **CsrfParser**：GET 頁面刮 `_csrf`（先用字串/正規式，必要時輕量 HTML parse）
- [x] 1.3 **SessionBootstrap**：處理 HiNetCDN LBSCookie（`?_cookie_check=1`）首次握手
- [x] 1.4 **AuthService.login**：`POST /access(idNo)` → GET `/login` → `POST /login(idNo,birthDate,phone)` → 判斷 302 `/member/tasks` 成功；區分「未註冊(導 /register)」與「三碼不符」錯誤
- [x] 1.5 Profile 設定畫面「我的資料」（存/讀 Keychain、遮罩顯示、FaceID 顯示完整）
  - [x] 1.5.1 出生日期改自製「年／月／日」三欄滾輪 sheet（民國/西元切換、預設民國、雙年份確認、換月自動夾日），不用系統日曆式 DatePicker；對外仍存 ISO `yyyy-MM-dd`。Onboarding 共用同一元件
  - [x] 1.5.2 App 開發語言鎖 `zh-Hant`（`project.yml` developmentLanguage、CFBundleDevelopmentRegion/CFBundleLocalizations）＋注入 `Locale(zh_Hant_TW)`，介面文案不吃裝置語系
  - [x] 1.5.3 移除「設定 — 資安中心」子頁，Face ID 開關／本機資料說明／立即清除（含確認 alert、清除後回 Onboarding）與版本聲明併入本頁「安全與隱私」區塊；頁首隱私聲明改為三點明列
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

## Phase 5 — 首次註冊（Phase 2 功能，非 MVP）
- [ ] 5.1 註冊表單 `POST /register` → 5.2 `/register/nhi-verify`(健保卡) → 5.3 `/register/otp`(簡訊，簡訊自動帶入)

## 橫向 / 收尾
- [ ] 推播提醒（每週上傳期開始 / 截止前 N 小時）
- [ ] 無障礙 AA（動態字級、對比、VoiceOver）
- [ ] 單元測試（AuthService/TasksService/解析器/KeychainStore）
- [ ] 資安自審（無 log 洩漏、無雲端呼叫、依賴審查）

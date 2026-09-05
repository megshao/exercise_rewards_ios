# App Review Notes — Sports Rewards 1.0

本檔案分兩部分：

- **Part A**：直接複製貼上到 App Store Connect 的 **App Review Information → Notes** 欄位（英文為主，關鍵處附中文）。
- **Part B**：**不要貼給 Apple**，是給提交者的內部備註——殘餘風險、我們無法自行消除的部分、以及送審前必須先處理的待辦。

---

# Part A — Paste into App Store Connect "Notes"

## 1. What this app is (and is not)

Sports Rewards is an **unofficial, personal-use companion app** for a public exercise campaign run in Taiwan ("揮汗有禮・全民動起來", operated on the government website `500.gov.tw`).

- The developer is an **independent individual** and is **not affiliated with, endorsed by, sponsored by, or authorized to represent** the Ministry of Sports or any government agency. 中文：**本 App 為非官方工具，與運動部及任何政府機關無隸屬、合作、贊助或授權關係。**
- The app does **not** impersonate the campaign or any agency. The App Store name is the neutral English name **"Sports Rewards"**; the campaign name is never used as the app name, and the icon contains no government emblem, agency name, or the string "500".
- The app has **no backend of its own**. It is a native HTTP client that acts on behalf of the user, using only credentials the user typed in themselves, against the user's own account.

### Where the "unofficial" disclosure appears
1. **In-app — "我的資料" (My Data) screen, bottom of the "安全與隱私" section**: a permanent footer reading `非官方工具` together with the privacy summary.
2. **In-app — first-run screen**: the disclosure text shown before the user enters any data.
3. **App Store description**: the very first paragraph states the app is unofficial and unaffiliated.

## 2. Demo account (required to review this app) — 示範帳號

Signing in normally requires a **real Taiwan national ID number, date of birth, and a Taiwan mobile number** that already exist on the government site. A reviewer cannot obtain those. We therefore ship a **fully disclosed demo mode**.

**Credentials (enter these in the app's own sign-in form):**

| Field (Chinese label in app) | Value |
|---|---|
| 身分證號 (ID number) | `A000000000` |
| 出生日期 (Date of birth) | `1990-01-01` |
| 手機號碼 (Mobile number) | `0900000000` |

**Step by step:**
1. Launch the app. The first screen is a welcome screen — tap the orange button **「開始使用」** (Get Started).
2. A 3-field form appears. In **身分證號**, type `A000000000` (case-insensitive, leading/trailing spaces are tolerated).
3. Tap the **出生日期** field. A custom year/month/day wheel opens. It defaults to the **ROC calendar (民國)**; use the segmented control at the top to switch to **西元** (Gregorian) and select **1990 / 1 / 1**, then tap **「完成」** (Done). (`1990-01-01` is `民國 79 年 1 月 1 日`.)
4. In **手機號碼**, type `0900000000`.
5. Tap **「送出並驗證」** (Submit). The app enters demo mode immediately.
6. A black banner **「示範模式 · 畫面為範例資料，未連線官方網站」** ("Demo mode · sample data, not connected to the official site") stays pinned at the top of every screen.
7. All four tabs are now fully explorable with mock data: **首頁** (Home), **任務** (Tasks, 14 periods), **健康** (Health), **券夾** (Wallet / vouchers), plus upload and redeem flows.
8. To leave demo mode: **我的資料 → 安全與隱私 → 「離開示範模式」**. Demo state also survives app restarts, so you can close and reopen the app and remain in demo mode.

**Why this is not an undocumented feature (Guideline 2.3.1):**
Demo mode is **deliberately not a hidden gesture or secret build flag**. Its entry point is the ordinary sign-in form that every user sees, it is documented here and in the Demo Account fields of App Store Connect, and it is visually announced by a permanent on-screen banner. `A000000000` is **not a valid ROC national ID** (it fails the official checksum), so no real user can trigger it by accident.

**What demo mode does technically** (source: `App/Sources/App/DemoMode.swift`):
- Every service is swapped for a `Mock*` implementation — **no network request of any kind is issued**.
- The profile is held in an in-memory store; **nothing is written to the Keychain**.
- Switching in or out of demo mode clears the local task cache in both directions.

## 3. Open source — transparency evidence

The complete source code is published under the **MIT license**. Every line that touches personal data, networking, or HealthKit can be audited independently.

- Repository: https://github.com/megshao/sports-rewards-ios
- Files a reviewer may find most relevant:
  - `App/Sources/App/DemoMode.swift` — the demo mode described above
  - `Sources/SportsRewardsKit/Networking/` — the domain allowlist and HTTPS enforcement
  - `Sources/SportsRewardsKit/Security/` — Keychain storage, log redaction
  - `App/project.yml` — the exact Info.plist and entitlements shown below

## 4. HealthKit usage — read-only, never transmitted

- The app requests **read access only**, for exactly three types: `stepCount`, `distanceWalkingRunning`, `appleExerciseTime`.
- Health data is used for **one purpose only**: showing the user their own daily activity on-device and telling them whether they have met the campaign threshold (8,000 steps, or 30 minutes of walking, or 5 km of running in a single day).
- **Health data is never transmitted anywhere.** It is not uploaded to the government site, not sent to the developer (there is no developer server), and not used to generate any image that gets uploaded. 中文：**健康資料只在裝置本機顯示，絕不外傳。**
- The app **never writes** to HealthKit. There is no code path that calls a HealthKit save/write API.
- The user is **not required** to grant Health access. If access is denied, the step ring simply shows a "not linked" placeholder and the rest of the app works normally.
- **Why `NSHealthUpdateUsageDescription` is present despite being read-only**: Apple's upload validation (**ITMS-90683**) rejects any binary carrying the HealthKit entitlement without both usage strings, even when only read access is requested. The string we ship is honest about this and reads: *「本 App 不會寫入任何健康資料，只讀取步數判斷今日是否達標」* ("This app never writes health data; it only reads step count to determine whether today's goal is met"). Its presence should not be read as an intent to write.

## 5. Networking — no backend of our own

- The app has **no server, no API, no analytics, no crash-reporting SDK, and zero third-party dependencies** (Foundation / SwiftUI / HealthKit only).
- The app connects to **exactly one domain: `500.gov.tw`** — the official campaign website, where the user already has an account.
- This is enforced **twice**:
  1. **App Transport Security** — `NSAllowsArbitraryLoads = false`, with a single exception entry for `500.gov.tw` requiring **TLS 1.2+ and forward secrecy**. No cleartext exception is granted to anything.
  2. **Client-side allowlist** — `URLSessionHTTPClient` rejects any request whose host is not `500.gov.tw` or a subdomain (suffix-spoofing such as `evil500.gov.tw` is explicitly blocked) and throws `blockedEgress`.
- The official site issues `302` redirects whose `Location` header is `http://`. The client **rewrites these back to `https://`** before following, so the session never downgrades to cleartext.
- Cookies (`LBSCookie`, `JSESSIONID`) live **in memory only** and are cleared on sign-out and on "clear local data".
- `WKAppBoundDomains` is declared as `["500.gov.tw"]`. The app currently **uses no script-injectable WebView at all** — account registration opens the official site in **external Safari** via `UIApplication.open`, not in an in-app WebView. The declaration is a forward-looking guarantee that no script could ever be injected anywhere but that one domain.

## 6. Data handling summary

| Data | Collected by developer | Stored where | Sent where |
|---|---|---|---|
| National ID, date of birth, mobile number | **No** (no server exists) | iOS Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, **not** iCloud-synced, **not** included in backups | Directly from the device to `500.gov.tw` at sign-in, to authenticate the user's own account |
| Health data (steps, distance, exercise time) | **No** | Read on demand from HealthKit; not persisted | **Nowhere** |
| Photo chosen for upload | **No** | Not persisted | Uploaded by the user to the user's own task on `500.gov.tw` |
| Logs / analytics | **No** | All logging goes through a single `SecureLog` entry point that redacts ID, birth date, phone, email, cookies, CSRF tokens, OTP and presigned URLs; debug output is compiled out of Release builds | Nowhere |

Only **three** personal fields are collected — the minimum the official sign-in form requires. The app deliberately does **not** ask for name, email, or national health insurance card number. Users can permanently erase everything from **我的資料 → 「立即清除本機資料」** (Clear local data), which wipes the Keychain, caches and cookies and returns the app to first-run state.

## 7. Point-by-point notes on specific guidelines

### 2.1 — App Completeness
Sign-in requires real government-issued credentials that a reviewer cannot obtain. This is why the fully documented **demo mode in §2** exists: it exercises every screen and every flow (sign-in, 14-period task dashboard, health summary, screenshot upload, voucher redemption, wallet) end-to-end with mock data and no network access. If any part of the demo is unclear, we will supply a screen recording on request.

### 2.3.1 — Accurate Metadata / no hidden features
The only conditional behaviour in the app is demo mode, and it is disclosed here, in the App Store Connect demo-account fields, and by a permanent on-screen banner while active. **There are no other hidden, dormant, or remotely-toggled features**, no remote configuration, no feature flags fetched from a server (there is no server), and no code that behaves differently for reviewers versus users beyond the sentinel credentials documented above.

### 4.1 — Copycats / Impersonation
The app is named **"Sports Rewards"** — a neutral English name that is not the campaign's name. The icon carries no agency mark, national emblem, or campaign branding. The first paragraph of the App Store description, the first-run screen, and the in-app My Data screen all state plainly that this is an unofficial tool with no affiliation. The campaign name appears only in explanatory prose ("an unofficial tool that helps you take part in the 揮汗有禮 campaign"), never as an identity claim.

### 5.1.1(ix) — Data collection for sensitive services
The app **does not operate a service that collects data**. There is no backend; the developer receives nothing. The three identity fields the user types are stored only in that user's own device Keychain and are transmitted only to `500.gov.tw`, the site where the user already holds an account, to sign that user in. This is functionally equivalent to a password manager filling a government login form on the user's behalf. The app requests no name, no email, and no health-insurance card number, and it never asks for data that the official sign-in form does not itself require.

### 5.1.3(i) — Health data and rewards
The app **never transmits HealthKit data**, so no health data is exchanged for any benefit. Health data is read on-device solely to display the user's own daily activity and to indicate, locally, whether the campaign threshold has been met. Uploads to the campaign site contain **a screenshot the user selects themselves from their photo library** — the app does not compose, generate, alter, or auto-fill any image from HealthKit data. Nor is health data shared with any third party, advertiser, or data broker; there is no third-party SDK in the binary at all. 中文：**健康資料唯讀、不外傳、不用於產生上傳圖片。**

### 5.2.2 — Third-party sites and services
The app acts **only on behalf of the individual user, on that user's own account**, using credentials the user entered themselves. It performs the same requests the user could perform manually in Safari, at human pace, with no polling, no bulk operations, no multi-account support, and no automated retry storms. It respects the site's rate limits (including the daily SMS OTP cap and resend countdown) and **never bypasses any identity verification** — household-registration checks, health-insurance-card verification and SMS OTP are all left entirely to the official site. Account registration is not performed in-app at all; the app opens the official registration page in external Safari.

### 4.2 — Minimum Functionality
The app is a native SwiftUI application, not a web wrapper. It contains no in-app browser. All screens (task dashboard, health summary, upload, redemption, wallet, data management) are natively rendered, and HTML from the official site is parsed into native models.

### 4.8 — Login Services
Sign-in is to the user's existing government-service account. Per 4.8, government/electronic-ID authentication is exempt from the Sign in with Apple requirement. No third-party social login is offered.

### 5.1.1(v) — Account deletion
The app does not create accounts, so there is no app account to delete. Users can permanently delete all locally stored data from within the app (**我的資料 → 「立即清除本機資料」**). The account itself lives on `500.gov.tw` and is managed there; our support page links to the official site's account management.

## 8. Contact

`TODO(待填：送審聯絡人姓名、Email、電話——App Store Connect 的 App Review Information 也需要同一組資料)`

---
---

# Part B — 內部備註（**不要貼給 Apple**）

## B1. 送審前必須先修掉的東西（目前程式碼與 Part A 的敘述不符）

| # | 問題 | 位置 | 為什麼是 blocker |
|---|---|---|---|
| 1 | 頁尾仍寫 `揮汗有禮 v0.1 · 非官方工具` | `App/Sources/Views/ProfileView.swift:233` | (a) 顯示名已定案 `Sports Rewards`，App 內卻用活動名當自稱——**這正是 4.1／5.2.1 想避免的事**；(b) 版本寫 v0.1，與送審的 1.0 不符，屬 metadata 不一致。建議改為 `Sports Rewards 1.0 · 非官方工具（與運動部無關）`。 |
| 2 | 首次啟動頁**沒有**非官方聲明 | `App/Sources/Views/OnboardingView.swift`（歡迎頁大標目前是「揮汗有禮」） | Part A §1 宣稱「三處揭露」，但目前**只有「我的資料」頁一處**。歡迎頁不但缺聲明，還把活動名當成 App 標題顯示。送審前必須：把大標改成 `Sports Rewards`（或中性標語），並在按鈕上方加一行「本 App 為非官方工具，與運動部無關」。 |
| 3 | App 內沒有開源 repo 連結 | `docs/PRD.md §5.9` 標為「待補」 | Review Notes 拿開源當透明佐證，App 內卻連不過去。建議在「我的資料 → 安全與隱私」加一列「原始碼（GitHub）」。 |

**在 1 和 2 修好之前，Part A §1 的「三處揭露」是不實敘述，不可送出。**

## B2. 你必須自己補的資訊（Part A 裡的 `TODO(待填)`）

1. 開源 repo 的公開網址（§3、B1-3 都要用）。
2. 送審聯絡人姓名、Email、電話（§8）。
3. 支援 URL 與隱私權政策 URL（見 `app-store-metadata.md` §7）。

## B3. 做完降險後仍然消不掉的殘餘風險

以下四項**不是文案能解決的**，寫在這裡讓你在送審前先決定要不要承擔（依據 `docs/app-review-risk.md`）：

| # | 殘餘風險 | 條號 | 你能做的準備 |
|---|---|---|---|
| 1 | **提交者身分**：功能牽涉政府服務與身分證號，Apple 有判例要求「由提供服務的法人提交」。以**個人開發者帳號**提交被拒的機率明顯高於組織帳號，而這無法用 Review Notes 說服。 | 5.1.1(ix) / 5.2.1 | 若有公司／協會，改用**組織帳號（D-U-N-S）**提交。若只能用個人帳號，先有被拒的心理準備，並準備好「無後端、不收資料」的技術佐證（Info.plist 截圖、allowlist 原始碼）。 |
| 2 | **授權文件**：5.2.2 允許 Apple 隨時要求「使用第三方服務的授權證明」。本 App 本質是非官方 client，你拿不出運動部的書面授權。 | 5.2.2 | 主動去函運動部求一紙「知悉、不反對」的回覆。**若對方明確反對，那就是不該上公開商店的訊號**，改走 TestFlight 或開源自簽。 |
| 3 | **官方 App 出現**：官方已在做「運動幣 App 需求調查」。官方 App 一上架，本 App 立刻升高成 impersonation 與被檢舉下架的目標。 | 4.1(b) | 無法預防。可先走 TestFlight 外部測試（≤10,000 人）涵蓋 14 週活動期，觀察 Apple 反應再決定是否上公開商店。 |
| 4 | **官網改版即失效**：純刮 HTML 對結構敏感，官網一改版 App 就不能用，Apple 可依 4.0 移除「stopped working」的 App。 | 4.0 | 解析器已集中管理便於快速更新；商店描述已預先告知使用者此限制（見 description「使用前請先知道」）。 |

## B4. 建議的散佈順序

1. **TestFlight 外部測試**先跑，涵蓋整個活動期，試 Apple 的 Beta App Review 反應。
2. 若順利且第 2 項授權問題有進展，再送公開 App Store。
3. 公開商店被拒時的後路：維持開源 + 使用者自行以 Xcode／AltStore 側載，與專案的開源定位一致。

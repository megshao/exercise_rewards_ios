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
- The app does contain **one third-party SDK** — Firebase Analytics and Crashlytics — for anonymous usage statistics and crash reports. It is **disabled by default** and only starts collecting if the user turns it on themselves. It never receives identity or health data. Full details in §5b.

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
- **Health data never enters the telemetry SDK either** (see §5b), even when the user has opted in. Not the raw values, and **not even a derived boolean such as "did the user hit today's goal"** — that derivation is explicitly forbidden in the source (`App/Sources/App/Telemetry.swift`, header comment, prohibited item #2), precisely because Guideline 5.1.3 forbids sharing HealthKit data with third parties. The only health-adjacent signal that can ever be sent is `health_auth_granted`, a boolean recording **whether the user granted read authorization** — it carries no measurement of any kind.
- The app **never writes** to HealthKit. There is no code path that calls a HealthKit save/write API.
- The user is **not required** to grant Health access. If access is denied, the step ring simply shows a "not linked" placeholder and the rest of the app works normally.
- **Why `NSHealthUpdateUsageDescription` is present despite being read-only**: Apple's upload validation (**ITMS-90683**) rejects any binary carrying the HealthKit entitlement without both usage strings, even when only read access is requested. The string we ship is honest about this and reads: *「本 App 不會寫入任何健康資料，只讀取步數判斷今日是否達標」* ("This app never writes health data; it only reads step count to determine whether today's goal is met"). Its presence should not be read as an intent to write.

## 5. Networking — no backend of our own

- The app has **no server and no API of its own**. The developer operates no backend and receives no personal data.
- Personal data (national ID, date of birth, mobile number) and the uploaded screenshot go to **exactly one domain: `500.gov.tw`** — the official campaign website, where the user already has an account.
- The app's own HTTP client is restricted to that one domain. This is enforced **twice**:
  1. **App Transport Security** — `NSAllowsArbitraryLoads = false`, with a single exception entry for `500.gov.tw` requiring **TLS 1.2+ and forward secrecy**. No cleartext exception is granted to anything.
  2. **Client-side allowlist** — `URLSessionHTTPClient` rejects any request whose host is not `500.gov.tw` or a subdomain (suffix-spoofing such as `evil500.gov.tw` is explicitly blocked) and throws `blockedEgress`.
- The official site issues `302` redirects whose `Location` header is `http://`. The client **rewrites these back to `https://`** before following, so the session never downgrades to cleartext.
- **Scope of that allowlist — stated plainly:** it is a check inside `URLSessionHTTPClient` and therefore governs **only requests the app itself issues**. The Firebase SDK uses its own `URLSession` and is **not** subject to it. When (and only when) the user has enabled telemetry, the SDK connects to Google endpoints: `app-analytics-services.com`, `firebaseinstallations.googleapis.com`, `firebase-settings.crashlytics.com`, `crashlyticsreports-pa.googleapis.com`, `firebaselogging.googleapis.com`. ATS still forces HTTPS for all of them. We are disclosing this proactively rather than letting the allowlist claim read as broader than it is.
- Cookies (`LBSCookie`, `JSESSIONID`) are stored in the app's sandbox container (protected by iOS data protection, not synced to iCloud), and are cleared on sign-out and on "clear local data" via `resetSession()`.
- `WKAppBoundDomains` is declared as `["500.gov.tw"]`. The app currently **uses no script-injectable WebView at all** — account registration opens the official site in **external Safari** via `UIApplication.open`, not in an in-app WebView. The declaration is a forward-looking guarantee that no script could ever be injected anywhere but that one domain.

## 5b. Third-party SDK and optional telemetry — Firebase Analytics / Crashlytics

We are disclosing this in full because the app also carries the HealthKit entitlement, and a reviewer is entitled to ask whether health data reaches Google. **It does not.**

**What is in the binary**
- `firebase-ios-sdk` **12.18.0**, via Swift Package Manager. Products used: `FirebaseAnalyticsCore`, `FirebaseCrashlytics`, `FirebaseCore`.
- SPM **resolves 13 packages**; only **6 are actually linked** into the app binary: `firebase-ios-sdk`, `GoogleAppMeasurement`, `GoogleDataTransport`, `GoogleUtilities`, `nanopb`, `promises`. (Both numbers are stated so they can be checked: the 13 are in `Package.resolved`, the 6 are in the release `SportsRewards.LinkFileList` and visible as resource bundles inside the `.app`.)
- We deliberately chose **`FirebaseAnalyticsCore`, not `FirebaseAnalytics`**. Its underlying measurement library is `GoogleAppMeasurementCore`, which **structurally has no IDFA collection capability**. The release binary links **neither `AdSupport` nor `AppTrackingTransparency` nor `AdServices`** — verifiable with `otool -l`. The app therefore cannot, and does not, present an App Tracking Transparency prompt. `PrivacyInfo.xcprivacy` declares `NSPrivacyTracking = false` with an empty tracking-domain list.

**It is off by default (opt-in)**
- Four Info.plist keys ship as `false`: `FIREBASE_ANALYTICS_COLLECTION_ENABLED`, `FirebaseCrashlyticsCollectionEnabled`, `GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED`, `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS`.
- The user must switch it on themselves at **我的資料 › 安全與隱私 › 「傳送匿名使用統計」** (My Data › Security & Privacy › "Send anonymous usage statistics").
- Reason for opt-in: `FirebaseApp.configure()` mints an app instance ID and emits `first_open` the moment it runs. Shipping it on would mean data leaves the device **before the user has even seen the switch**.
- **A reviewer using demo mode will therefore generate no telemetry at all** — demo mode is the one gate in the code with no bypass, and it also flips the SDK-level collection flags off. This is intentional, and it is why crashes during review would not reach us.

**What can be sent, at most**
Everything that can leave the app goes through a single file, `App/Sources/App/Telemetry.swift`; every other file is forbidden from importing the Firebase modules. Event names, parameter values, user properties and crash keys are all **closed Swift enums**, so a free-form string cannot be transmitted — it does not compile.
- Events: `app_launched`, `screen_view` (screen name is itself a closed enum: `onboarding`, `home`, `tasks`, `health`, `wallet`, `profile`, `redeem`, `voucher`, `upload`), `telemetry_preference_changed`. Plus Firebase's own automatic events (`first_open`, `session_start`, `user_engagement`, `app_update`).
- User properties: two booleans only — `health_auth_granted`, `onboarding_completed`.
- Crash keys: `is_demo_mode`, `last_screen`.
- Non-fatal errors: only the `NSError` domain and code, plus a message that has been run through the project's `Redact.scrub`. The original `userInfo` is **never** handed to Crashlytics.

**What can never be sent, even when enabled**
National ID, date of birth, mobile number (in any form — raw, hashed, truncated or concatenated); any HealthKit value or anything derived from one; the uploaded screenshot or any metadata about it; voucher codes and barcodes; session cookies, CSRF tokens or OTPs; any free text the user typed; any raw error string from the campaign website.

This is enforced by **mechanism, not discipline**. Before anything is transmitted it passes four gates: (1) SDK not configured — no `GoogleService-Info.plist`, everything is a no-op; (2) demo mode — no bypass exists; (3) user preference off; (4) content scan — if any parameter matches the project's sensitive-data patterns the event is dropped, and in DEBUG builds the app deliberately trips an `assertionFailure` so the mistake surfaces during development rather than being silently swallowed in production.

**Configuration file**: `GoogleService-Info.plist` is excluded from version control because the repository is public; a `.template` is committed in its place. If the real file is absent, `Telemetry.configure()` returns early and the entire telemetry layer is inert — the app still builds and runs.

## 6. Data handling summary

| Data | Collected by developer | Stored where | Sent where |
|---|---|---|---|
| National ID, date of birth, mobile number | **No** (no server exists) | iOS Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, **not** iCloud-synced, **not** included in backups | Directly from the device to `500.gov.tw` at sign-in, to authenticate the user's own account |
| Health data (steps, distance, exercise time) | **No** | Read on demand from HealthKit; not persisted | **Nowhere** |
| Photo chosen for upload | **No** | Not persisted | Uploaded by the user to the user's own task on `500.gov.tw` |
| On-device logs | **No** | All logging goes through a single `SecureLog` entry point that redacts ID, birth date, phone, email, cookies, CSRF tokens, OTP and presigned URLs; debug output is compiled out of Release builds. It is **never** bridged to Crashlytics | Nowhere |
| Anonymous usage events and crash reports | **Aggregated only, and only after opt-in** | Not persisted locally beyond the SDK's own send queue | **Google (Firebase)** — but only once the user enables 「傳送匿名使用統計」. Contains no identity data and no health data; see §5b |

The one row above that is not "No" is the optional telemetry, and it carries **no personal field at all** — see §5b for the exhaustive list of what it can and cannot contain.

Only **three** personal fields are collected — the minimum the official sign-in form requires. The app deliberately does **not** ask for name, email, or national health insurance card number. Users can permanently erase everything from **我的資料 → 「立即清除本機資料」** (Clear local data), which wipes the Keychain, caches and cookies and returns the app to first-run state.

## 7. Point-by-point notes on specific guidelines

### 2.1 — App Completeness
Sign-in requires real government-issued credentials that a reviewer cannot obtain. This is why the fully documented **demo mode in §2** exists: it exercises every screen and every flow (sign-in, 14-period task dashboard, health summary, screenshot upload, voucher redemption, wallet) end-to-end with mock data and **no network access from the app's own HTTP client**. If any part of the demo is unclear, we will supply a screen recording on request.

Note for completeness: demo mode also forces the telemetry SDK's collection flags off, so **no analytics or crash reports are produced while a reviewer is in demo mode either** (§5b). If the app were to crash during review, we would not receive that report — we accept that trade-off rather than collect data from someone who never consented.

### 2.3.1 — Accurate Metadata / no hidden features
The only conditional behaviour in the app is demo mode, and it is disclosed here, in the App Store Connect demo-account fields, and by a permanent on-screen banner while active. **There are no hidden, dormant, or remotely-toggled features**, and no code that behaves differently for reviewers versus users beyond the sentinel credentials documented above.

Two things are worth stating explicitly rather than leaving to inference:
- **The telemetry switch is a user-facing setting, not a hidden flag.** It lives in plain sight at 我的資料 › 安全與隱私, ships off, and its entire event surface is enumerated in §5b.
- **We do not operate any remote configuration or feature-flag service** — there is no developer server to host one. The Firebase Crashlytics SDK does fetch its own operational settings from `firebase-settings.crashlytics.com` when the user has enabled crash reporting; that is Google's SDK configuring itself, and it cannot change any behaviour or feature of this app.

### 4.1 — Copycats / Impersonation
The app is named **"Sports Rewards"** — a neutral English name that is not the campaign's name. The icon carries no agency mark, national emblem, or campaign branding. The first paragraph of the App Store description, the first-run screen, and the in-app My Data screen all state plainly that this is an unofficial tool with no affiliation.

**Disclosed proactively:** the Home tab displays the campaign's Chinese name (揮汗有禮) as a section heading, so that users who came for that campaign recognise they are in the right place. We want to be explicit that this is a **descriptive reference to the campaign the app helps with, not a claim of identity or endorsement**. The app's own identity — on the App Store, on the Home screen icon, in the About footer (`Sports Rewards v1.0.0 · 非官方工具`), and on the first-run screen — is consistently **Sports Rewards**, and the App Store subtitle reads 「揮汗有禮非官方串接」, which places the word **非官方 ("unofficial")** directly against the campaign name. If the review team would prefer the campaign name removed from that heading as well, we will change it immediately on request.

### 5.1.1(ix) — Data collection for sensitive services
The app **does not operate a service that collects identity data**. There is no developer backend, and the developer receives none of the user's identity data. The three identity fields the user types are stored only in that user's own device Keychain and are transmitted only to `500.gov.tw`, the site where the user already holds an account, to sign that user in.

The app does contain an **optional, off-by-default** analytics and crash-reporting SDK (§5b). It is worth being precise about the boundary rather than glossing it: **none of the three identity fields — in any form, including hashed, truncated or concatenated — can reach it.** The transmittable surface is a set of closed Swift enums plus a content scan; a free-form string containing personal data does not compile, and if one were somehow constructed it would be dropped at the gate. The user can also decline it entirely, which is the shipping default. This is functionally equivalent to a password manager filling a government login form on the user's behalf. The app requests no name, no email, and no health-insurance card number, and it never asks for data that the official sign-in form does not itself require.

### 5.1.3(i) — Health data and rewards
The app **never transmits HealthKit data**, so no health data is exchanged for any benefit. Health data is read on-device solely to display the user's own daily activity and to indicate, locally, whether the campaign threshold has been met. Uploads to the campaign site contain **a screenshot the user selects themselves from their photo library** — the app does not compose, generate, alter, or auto-fill any image from HealthKit data.

**Because this app now contains a Google SDK, we want to answer the obvious follow-up before it is asked: no HealthKit data reaches Firebase.**
- The set of values the telemetry layer is capable of transmitting is a closed enum (§5b). There is no member of it that carries a step count, a distance, an exercise duration, or any other measurement.
- **We deliberately do not send even a derived boolean** such as "did this user meet today's goal". That value would be information obtained from HealthKit, and 5.1.3 does not become satisfied by reducing health data to one bit. The prohibition is written into the source file's header as a standing rule for future contributors, with this guideline cited as the reason.
- The one health-adjacent signal that exists is `health_auth_granted` — a boolean recording **whether the user granted read authorization**. It is an app-permission state, not a measurement.
- Health data is not shared with any advertiser or data broker, and the binary links no advertising identifier framework at all (`AdSupport`, `AppTrackingTransparency` and `AdServices` are all absent — verifiable with `otool -l`).
- In the App Privacy questionnaire, **Health and Fitness are both declared Not Collected**, and that answer is unchanged by the addition of the SDK.

中文：**健康資料唯讀、不外傳、不用於產生上傳圖片，也絕不進入第三方遙測——連「今日是否達標」這種由步數推導的布林值都不送。**

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

## B1. 送審前必須先修掉的東西（狀態：3/3 已修）

| # | 問題 | 位置 | 狀態 |
|---|---|---|---|
| 1 | 頁尾寫 `揮汗有禮 v0.1 · 非官方工具` | `App/Sources/Views/ProfileView.swift` | ✅ **已修**：改為 `Sports Rewards v{CFBundleShortVersionString} · 非官方工具`，版本號改讀 Bundle，不再硬編碼。 |
| 2 | 首次啟動頁沒有非官方聲明 | `App/Sources/Views/OnboardingView.swift` | ✅ **已修**：歡迎頁主標改為 `Sports Rewards`、副標說明用途，並新增非官方聲明卡。Part A §1 的「三處揭露」現已成立。 |
| 3 | App 內沒有開源 repo 連結 | 「我的資料 › 安全與隱私」 | ✅ **已修**：新增「原始碼」一列，以外部 Safari 開啟 https://github.com/megshao/sports-rewards-ios（不用 WebView）。 |

## B1b. 已知並接受的曝險：首頁標頭保留活動名

`App/Sources/Views/HomeView.swift` 的首頁標頭仍以大字顯示「揮汗有禮」。

- **這是使用者在知悉風險後的明確決定**（2026-09-05），理由是活動參加者的辨識度。
- **代價**：這是全 App 對 guideline 4.1／5.2.1 曝險最大的一處——審查員打開 App，最顯眼的自稱是官方活動名，而商店名稱卻是 Sports Rewards。若官方日後推出自己的 App，此處會是最先被指為 impersonation 的地方。
- **緩解**：已在 Part A §4.1 **主動向審查員揭露**這件事並說明它是描述性引用，同時表明「若審查團隊希望移除，我們立即照辦」。主動講比被抓到好。
- **若被以 4.1／5.2.1 退件**：第一個該改的就是這裡（改成 `Sports Rewards` 或 `揮汗有禮·非官方`），成本只有一行文字。

## B1c. 2026-09-06 加入 Firebase 之後的新增殘餘風險

這次變更把「零第三方 SDK」這個乾淨的辯護點換掉了。以下是換來的曝險，依嚴重度排序。

| # | 殘餘風險 | 條號 | 現況與可做的準備 |
|---|---|---|---|
| 1 | **帶 HealthKit entitlement 的 App 裡出現 Google SDK**。審查員看到這個組合，第一個問題必然是「健康資料有沒有進 Firebase」。答案是沒有，但這從「不必解釋」變成了「必須解釋」。 | 5.1.3(i) | Part A §5b 與 §7 的 5.1.3(i) 段已主動、逐點揭露（封閉列舉、連達標布林都不送、`health_auth_granted` 只是授權狀態）。**這是本次變更最大的一筆代價**，而且無法靠文案消除，只能靠「講在前面」降低。 |
| 2 | **隱私標籤必須與實際行為完全一致**。四格從 Not Collected 改成 Collected，任何一格填錯就是 metadata 違規（可下架）。 | 5.1.1 / 5.1.2 | 依 `docs/release/privacy-labels.md`（2026-09-06 大改版）逐格填；送審前對照 `PrivacyInfo.xcprivacy` 再核一次，兩邊不可以不一致。**Location › Coarse Location 那格仍是 `TODO(待確認)`**，送審前務必查 Google 當時的官方對照表。 |
| 3 | **「預設關閉」這句話必須永遠為真**。它是本次變更最主要的辯護點，同時出現在 Review Notes、隱私政策、官網、商店描述與 CHANGELOG。任何人把 `Telemetry.defaultEnabled` 改成 `true`、或改動那四個 Info.plist 旗標，這五個地方會同時變成不實陳述。 | 2.3.1 | 建議在 CI 加一條檢查：`defaultEnabled == false` 且四個旗標為 `false`，否則 fail。**目前沒有這條檢查。** |
| 4 | **送審 archive 必須含正式的 `GoogleService-Info.plist`**。它不進版控，缺檔時遙測全程 no-op——使用者打開開關也不會有任何反應。這不會被拒審，但會變成「宣稱有、實際沒有」的落差。 | — | 打包前確認 `App/Resources/GoogleService-Info.plist` 存在。已列入 `app-store-metadata.md` §11 檢查清單。 |
| 5 | **審查期間的當機收不到**。示範模式是唯一沒有 bypass 的閘門，審查員又從未同意過遙測，所以審查過程中任何當機都不會回報給我們。 | — | 這是 opt-in 的必然代價，接受。補救方式是送審前自己在示範模式把全部流程跑一遍。 |
| 6 | **開源 + 公開 repo 的灌水風險**。`GoogleService-Info.plist` 雖不進版控，但 App 一上架，任何人都可以從 IPA 取出設定並灌假事件。 | — | 在 GCP 主控台**限制 API key 的 bundle ID**。`TODO(待確認：是否已設定)` |
| 7 | **實作與 `docs/analytics-plan.md` §6.6 有落差**（見下方 B1d），其中「首次啟動的同意卡片」缺席，代表使用者只能靠自己翻到設定頁才知道有這個開關。 | — | 這對審查無害（預設關比預設開安全），但它讓「使用者知情同意」的說法弱一些。要補的話是 UI 工作，不在文件範圍。 |

## B1d. 實作與 `docs/analytics-plan.md` 的已知落差（送審前請自行決定要不要補）

`analytics-plan.md` 是設計提案，實作只落實了其中一部分。以下差異**目前不影響上面任何一句對外宣稱的真偽**，但會影響辯護力道：

| 計畫 §6.6 建議 | 實作現況 | 影響 |
|---|---|---|
| `FirebaseAutomaticScreenReportingEnabled = NO` | **未設定** | Firebase 會自動記錄 `screen_view`（SwiftUI 下多半是 hosting controller 的類別名）。這仍不含個資，但「畫面名來自封閉列舉」這句話只適用於我們自己送的事件，**不適用於 SDK 自動送的那些**。Part A §5b 已把自動事件單獨列出，沒有把它們算進封閉列舉。 |
| `FirebaseAppDelegateProxyEnabled = NO` | **未設定**（`GoogleUtilities-AppDelegateSwizzler` 確實有被連結） | 本 App 無推播，swizzling 沒有實際用途，但它存在。 |
| `FirebaseDataCollectionDefaultEnabled = NO`、`GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE` / `_AD_USER_DATA` | **未設定** | 目前靠已設定的四個旗標達成預設關閉，行為上是對的；但少了一層「全產品總開關」。 |
| 關閉同意時 `Analytics.resetAnalyticsData()` + `deleteUnsentReports()`（§6.4） | **未實作**。`setUserEnabled(false)` 只關收集旗標，`resetPreference()` 只重設偏好 | 「關掉即刻停止收集」為真；但**已在佇列中尚未送出的當機報告仍可能送出**，且 app instance ID 不會重生。對外文案目前都寫「停止收集」而非「刪除已送出資料」，措辭上沒有說謊，但這是最值得補的一項。 |
| 首次啟動的同意卡片（§6.2） | **未實作**，只有設定頁的開關 | 見 B1c #7。 |

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

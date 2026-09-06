# App Review Notes — Sports Rewards 1.0

本檔案分三部分：

- **Part A**：完整論述版，作為所有對外說法的單一事實來源。**它有 31,016 字元，塞不進 App Store Connect**（Notes 欄位上限 4,000 字元），所以不要直接貼。
- **Part A-短**：實際貼進 **App Review Information → Notes** 的 3,975 字元版本，2026-09-06 已寫入 ASC。改 Part A 的任何對外說法時，這一份要一起改。
- **Part B**：**不要貼給 Apple**，是給提交者的內部備註——殘餘風險、我們無法自行消除的部分、以及送審前必須先處理的待辦。

---

# Part A — 完整論述版（**不要直接貼**，超過 4,000 字元上限；要貼的是 Part A-短）

## 1. What this app is (and is not)

Sports Rewards is an **unofficial, personal-use companion app** for a public exercise campaign run in Taiwan ("揮汗有禮・全民動起來", operated on the government website `500.gov.tw`).

- The developer is an **independent individual** and is **not affiliated with, endorsed by, sponsored by, or authorized to represent** the Ministry of Sports or any government agency. 中文：**本 App 為非官方工具，與運動部及任何政府機關無隸屬、合作、贊助或授權關係。**
- The app does **not** impersonate the campaign or any agency. The App Store name is the neutral English name **"Sports Rewards"**; the campaign name is never used as the app name, and the icon contains no government emblem, agency name, or the string "500".
- The app has **no backend of its own**. It is a native HTTP client that acts on behalf of the user, using only credentials the user typed in themselves, against the user's own account.
- The app does contain **one third-party SDK** — Firebase Analytics and Crashlytics — for anonymous usage statistics and crash reports. **Nothing about it runs until the user has read and accepted the mandatory first-run disclaimer, which states in plain language that the app sends anonymous usage records and crash reports to Google Firebase.** Once accepted, it is on by default and can be switched off at any time. It never receives identity data, and the app holds no health data at all. Full details in §5b.

### Where the "unofficial" disclosure appears
1. **In-app — "我的資料" (My Data) screen, bottom of the "安全與隱私" section**: a permanent footer reading `非官方工具` together with the privacy summary.
2. **In-app — mandatory first-run disclaimer**: a blocking screen shown before onboarding and before the user enters any data. It requires an explicit checkbox and states three things: this is an unofficial tool, campaign entitlements follow the official announcements, and the app sends anonymous, non-personal usage statistics to Google Firebase (switchable off at any time). See §5b.
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
1. Launch the app. The first screen is a short welcome page (app icon, **Sports Rewards**, and a one-line note that this is an unofficial tool). Tap **「開始使用」** (Get started).
2. **A mandatory disclaimer** (「使用前請先確認」) is shown next, before any data entry. Read it, tick the checkbox, and tap **「同意並開始使用」** (Agree and start). This screen is also where the app discloses that it sends anonymous usage statistics to Google Firebase — see §5b for why the timing matters. **Nothing Firebase-related has run up to this point**, the welcome page included.
3. A 3-field form appears. In **身分證號**, type `A000000000` (case-insensitive, leading/trailing spaces are tolerated).
4. Tap the **出生日期** field. A custom year/month/day wheel opens. It defaults to the **ROC calendar (民國)**; use the segmented control at the top to switch to **西元** (Gregorian) and select **1990 / 1 / 1**, then tap **「完成」** (Done). (`1990-01-01` is `民國 79 年 1 月 1 日`.)
5. In **手機號碼**, type `0900000000`.
6. Tap **「送出並驗證」** (Submit). The app enters demo mode immediately.
7. A black banner **「示範模式 · 畫面為範例資料，未連線官方網站」** ("Demo mode · sample data, not connected to the official site") stays pinned at the top of every screen.
8. All three tabs are now fully explorable with mock data: **首頁** (Home), **任務** (Tasks, 14 periods), **券夾** (Wallet / vouchers), plus the upload, redeem and voucher-item flows.
9. To leave demo mode: **我的資料 → 安全與隱私 → 「離開示範模式」**. Demo state also survives app restarts, so you can close and reopen the app and remain in demo mode.

**Why this is not an undocumented feature (Guideline 2.3.1):**
Demo mode is **deliberately not a hidden gesture or secret build flag**. Its entry point is the ordinary sign-in form that every user sees, it is documented here and in the Demo Account fields of App Store Connect, and it is visually announced by a permanent on-screen banner. `A000000000` is **not a valid ROC national ID** (it fails the official checksum), so no real user can trigger it by accident.

**What demo mode does technically** (source: `App/Sources/App/DemoMode.swift`):
- Every service is swapped for a `Mock*` implementation — **no network request of any kind is issued**.
- The profile is held in an in-memory store; **nothing is written to the Keychain**.
- Switching in or out of demo mode clears the local task cache in both directions.
- **No telemetry event of any kind is emitted while demo mode is active** — demo mode is the first gate in `Telemetry.gate(...)` and the only one with no bypass, and the SDK-level collection flags are forced off as well.

**One thing we want to state before you notice it yourselves** (see §5b): the disclaimer in step 1 comes *before* onboarding, and demo mode is entered *inside* onboarding. So the order a reviewer actually experiences is **accept the disclaimer → Firebase initialises once → then enter demo mode**. A reviewer's device will therefore contact Google once, at the moment of acceptance. From the point demo mode starts, no events are sent. We consider this the correct trade-off: the disclosure happens before anything is transmitted, which is the property that matters.

## 3. Open source — transparency evidence

The complete source code is published under the **MIT license**. Every line that touches personal data or networking can be audited independently.

- Repository: https://github.com/megshao/sports_rewards_ios
- Files a reviewer may find most relevant:
  - `App/Sources/App/DemoMode.swift` — the demo mode described above
  - `Sources/SportsRewardsKit/Networking/` — the domain allowlist and HTTPS enforcement
  - `Sources/SportsRewardsKit/Security/` — Keychain storage, log redaction
  - `App/project.yml` — the exact Info.plist and entitlements shown below

## 4. HealthKit — not used at all

**This app does not use HealthKit.** There is nothing to review here, and we state it explicitly because an earlier build did.

- The binary carries **no HealthKit entitlement** (`App/project.yml` declares no entitlements file at all) and **no `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`** — the user is never shown a Health permission prompt.
- There is **no code path that reads, writes, or derives anything from health data**. `HealthKit` is not imported anywhere in the source.
- The activity record submitted to the campaign site is **a screenshot the user picks themselves from their photo library** (`PhotosPicker`). The app does not compose, generate, alter, or auto-fill any image.
- 中文：**本版完全不讀取健康資料，也不會出現健康權限提示。**

Earlier builds read step count, walking/running distance and exercise time (read-only, never transmitted). That feature has been **removed in its entirety** — entitlement, usage strings, the Health tab, the step ring on the home screen, and the two telemetry events that recorded the link action. Nothing about health remains.

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

We are disclosing this in full because a third-party SDK in a privacy-forward app deserves a straight answer about what leaves the device. (The app carries no HealthKit entitlement and reads no health data — see §4 — so the question of health data reaching Google does not arise.)

**What is in the binary**
- `firebase-ios-sdk` **12.18.0**, via Swift Package Manager. Products used: `FirebaseAnalyticsCore`, `FirebaseCrashlytics`, `FirebaseCore`.
- SPM **resolves 13 packages**; only **6 are actually linked** into the app binary: `firebase-ios-sdk`, `GoogleAppMeasurement`, `GoogleDataTransport`, `GoogleUtilities`, `nanopb`, `promises`. (Both numbers are stated so they can be checked: the 13 are in `Package.resolved`, the 6 are in the release `SportsRewards.LinkFileList` and visible as resource bundles inside the `.app`.)
- We deliberately chose **`FirebaseAnalyticsCore`, not `FirebaseAnalytics`**. Its underlying measurement library is `GoogleAppMeasurementCore`, which **structurally has no IDFA collection capability**. The release binary links **neither `AdSupport` nor `AppTrackingTransparency` nor `AdServices`** — verifiable with `otool -l`. The app therefore cannot, and does not, present an App Tracking Transparency prompt. `PrivacyInfo.xcprivacy` declares `NSPrivacyTracking = false` with an empty tracking-domain list.

**Disclosure first, then explicit consent, then on by default**

We want to describe this accurately rather than flatteringly. **This is not opt-in.** It is: *disclose → the user actively consents → on by default → off at any time.*

- **Nothing Firebase-related executes until the user accepts the first-run disclaimer.** The disclaimer is a blocking screen shown before onboarding (`App/Sources/Views/DisclaimerView.swift`). It states that the app sends anonymous usage records and crash reports to Google Firebase, that no personal data is included, and that it can be turned off at any time. The mandatory checkbox text covers consent to sending anonymous, non-personal usage statistics. Tapping 「同意並開始使用」 calls `DisclaimerConsent.record()`, which calls `Telemetry.configure()` — **that call is the first line of Firebase code the app ever executes**.
- **Why the boundary is "does it run at all", not "is the flag off":** `FirebaseApp.configure()` mints an app instance ID and emits `first_open` the moment it runs, and Firebase Installations contacts `firebaseinstallations.googleapis.com` for an installation ID **even when both collection flags are `false`**. A promise of "nothing is sent" can therefore only be kept by not initialising the SDK at all.
- `Telemetry.configure()` has **three preconditions; if any fails, nothing is initialised**: (1) the disclaimer has not been accepted, (2) the user has switched telemetry off, (3) demo mode is active.
- **After acceptance, the setting defaults to on.** The user can switch it off at any time at **我的資料 › 安全與隱私 › 「傳送匿名使用統計」** (My Data › Security & Privacy › "Send anonymous usage statistics"). 「立即清除本機資料」 (Clear local data) resets both the consent record and the telemetry preference, so the next cold launch shows the disclaimer again and Firebase does not run until it is accepted again.
- **Four Info.plist keys still ship as `false`**: `FIREBASE_ANALYTICS_COLLECTION_ENABLED`, `FirebaseCrashlyticsCollectionEnabled`, `GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED`, `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS`. These are the **cold-start defaults**, overwritten by `applyCollectionFlags` from the user's preference after initialisation. They are kept `false` to guarantee "no collection before `configure()` runs" — they are no longer a claim that the feature is off by default.

**What a reviewer will actually observe** — stated up front, because you would find it anyway:
- Accepting the disclaimer (step 1 of §2) initialises Firebase and produces one `first_open` plus one Firebase Installations request. **A reviewer's device will contact Google once, at that moment.**
- Demo mode is entered *afterwards*, inside the onboarding sign-in form. From that point on **no telemetry event is emitted at all** — demo mode is the first gate in the code and the only one with no bypass, and the SDK-level collection flags are forced off.
- Consequence we accept: **a crash during review would still not reach us**, because demo mode suppresses reporting. We would rather lose those reports than collect from a session the user is only demonstrating.
- We could avoid the initial contact entirely by deferring initialisation until a successful real sign-in, but that would discard the entire onboarding funnel — the part we most need in order to fix the app. We chose to disclose the behaviour instead of hiding it behind a timing trick.

**What can be sent, at most**
Everything that can leave the app goes through a single file, `App/Sources/App/Telemetry.swift`; every other file is forbidden from importing the Firebase modules. Event names, parameter values, user properties and crash keys are all **closed Swift enums**, so a free-form string cannot be transmitted — it does not compile.
- Events: 26 closed-enum cases covering screen views and the sign-in / task-fetch / upload / redeem / voucher funnels — `screen_view` (screen name is itself a closed enum: `onboarding_welcome`, `onboarding_form`, `home`, `tasks`, `wallet`, `profile`, `upload`, `screenshot`, `redeem`, `vendor_intro`, `voucher`), `login`, `login_failed`, `tasks_fetch`, `upload_pick`/`upload_submit`/`upload_result`, `redeem_options`/`redeem_select`/`redeem_cancel`/`redeem_submit`/`redeem_result`, `voucher_open`/`voucher_otp_send`/`voucher_otp_verify`/`voucher_reveal`, `voucher_mark_used` (a boolean recording that the user flagged one of their own vouchers as spent — the campaign site has no such state, so this is a purely local note; it carries no identifier), `profile_save`, `local_data_clear`, `site_error`, `consent_granted`, and a few more of the same shape. Every parameter value is a closed-enum raw value or a small bounded integer. Plus Firebase's own automatic events (`first_open`, `session_start`, `user_engagement`, `app_update`).
- User properties: **none at all.** `UserProperty` is declared as an empty, uninhabitable Swift enum (`enum UserProperty: Sendable {}`), so no user property can be constructed, and `Analytics.setUserProperty` has no call site anywhere in the project.
- Crash keys: 13 closed-enum cases — `build_channel`, `demo_mode`, `screen`, `onboarding_step`, `session_state`, `tasks_cache`, `current_period`, `current_state`, `last_endpoint`, `last_status`, `upload_stage`, `voucher_stage`, `consent_source`.
- Non-fatal errors: `recordNonFatal` **does not accept an `Error` object at all**. It takes a pre-classified `TelemetryIssue` enum plus an optional endpoint enum and HTTP status code, and builds a clean `NSError` from those. Server response text and the original `userInfo` are therefore structurally unable to reach Crashlytics — this is enforced by the function signature, not by a sanitising step that could be bypassed.

**What can never be sent, even when enabled**
National ID, date of birth, mobile number (in any form — raw, hashed, truncated or concatenated); the uploaded screenshot or any metadata about it; voucher codes and barcodes; session cookies, CSRF tokens or OTPs; any free text the user typed; any raw error string from the campaign website.

This is enforced by **mechanism, not discipline**. Before anything is transmitted it passes six gates, in this order: (1) demo mode — no bypass exists; (2) screenshot mode — events from automated screenshot runs never enter production data; (3) user preference off; (4) SDK not configured — with no `GoogleService-Info.plist` everything is a no-op; (5) content scan — if any parameter matches the project's sensitive-data patterns the event is dropped; (6) integer range check — every integer parameter must be a registered key whose value falls inside a narrow declared range, so an identifier or timestamp smuggled in as a number is rejected. Gates (5) and (6) additionally trip an `assertionFailure` in DEBUG builds, so the mistake surfaces during development rather than being silently swallowed in production.

**Configuration file**: `GoogleService-Info.plist` is excluded from version control because the repository is public; a `.template` is committed in its place. If the real file is absent, `Telemetry.configure()` returns early and the entire telemetry layer is inert — the app still builds and runs.

## 6. Data handling summary

| Data | Collected by developer | Stored where | Sent where |
|---|---|---|---|
| National ID, date of birth, mobile number | **No** (no server exists) | iOS Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, **not** iCloud-synced, **not** included in backups | Directly from the device to `500.gov.tw` at sign-in, to authenticate the user's own account |
| Photo chosen for upload | **No** | Not persisted | Uploaded by the user to the user's own task on `500.gov.tw` |
| On-device logs | **No** | All logging goes through a single `SecureLog` entry point that redacts ID, birth date, phone, email, cookies, CSRF tokens, OTP and presigned URLs; debug output is compiled out of Release builds. It is **never** bridged to Crashlytics | Nowhere |
| Anonymous usage events and crash reports | **Aggregated only, and only after the user accepts the first-run disclaimer** | Not persisted locally beyond the SDK's own send queue | **Google (Firebase)** — never before the disclaimer is accepted; on by default afterwards, and switchable off at any time via 「傳送匿名使用統計」. Contains no identity data; see §5b |

The one row above that is not "No" is the optional telemetry, and it carries **no personal field at all** — see §5b for the exhaustive list of what it can and cannot contain.

Only **three** personal fields are collected — the minimum the official sign-in form requires. The app deliberately does **not** ask for name, email, or national health insurance card number. Users can permanently erase everything from **我的資料 → 「立即清除本機資料」** (Clear local data), which wipes the Keychain, caches and cookies and returns the app to first-run state.

## 7. Point-by-point notes on specific guidelines

### 2.1 — App Completeness
Sign-in requires real government-issued credentials that a reviewer cannot obtain. This is why the fully documented **demo mode in §2** exists: it exercises every screen and every flow (sign-in, 14-period task dashboard, screenshot upload, redemption, per-vendor item catalogue, wallet, voucher barcode) end-to-end with mock data and **no network access from the app's own HTTP client**. If any part of the demo is unclear, we will supply a screen recording on request.

Note for completeness, stated precisely: demo mode forces the telemetry SDK's collection flags off and is the first, un-bypassable gate in the code, so **no analytics or crash reports are produced while a reviewer is in demo mode**. If the app were to crash during review, we would not receive that report — we accept that trade-off. What demo mode does *not* prevent is the one-time Firebase initialisation that happens when the reviewer accepts the first-run disclaimer, which comes before onboarding and therefore before demo mode is reachable; see §2 and §5b. We are stating this rather than letting you discover an unexplained Google request.

### 2.3.1 — Accurate Metadata / no hidden features
The only conditional behaviour in the app is demo mode, and it is disclosed here, in the App Store Connect demo-account fields, and by a permanent on-screen banner while active. **There are no hidden, dormant, or remotely-toggled features**, and no code that behaves differently for reviewers versus users beyond the sentinel credentials documented above.

Two things are worth stating explicitly rather than leaving to inference:
- **The telemetry switch is a user-facing setting, not a hidden flag.** It lives in plain sight at 我的資料 › 安全與隱私, its existence is disclosed on the mandatory first-run screen before it can collect anything, and its entire event surface is enumerated in §5b. We describe it in our own store listing and privacy policy as "on by default after you consent", not as opt-in, because that is what it is.
- **We do not operate any remote configuration or feature-flag service** — there is no developer server to host one. The Firebase Crashlytics SDK does fetch its own operational settings from `firebase-settings.crashlytics.com` once telemetry is running; that is Google's SDK configuring itself, and it cannot change any behaviour or feature of this app.

### 4.1 — Copycats / Impersonation
The app is named **"Sports Rewards"** — a neutral English name that is not the campaign's name. The icon carries no agency mark, national emblem, or campaign branding. The first paragraph of the App Store description, the first-run screen, and the in-app My Data screen all state plainly that this is an unofficial tool with no affiliation.

**Disclosed proactively:** the Home tab displays the campaign's Chinese name (揮汗有禮) as a section heading, so that users who came for that campaign recognise they are in the right place. We want to be explicit that this is a **descriptive reference to the campaign the app helps with, not a claim of identity or endorsement**. The app's own identity — on the App Store, on the Home screen icon, in the About footer (`Sports Rewards v1.0.0 · 非官方工具`), and on the first-run screen — is consistently **Sports Rewards**, and the App Store subtitle reads 「揮汗有禮非官方串接」, which places the word **非官方 ("unofficial")** directly against the campaign name. If the review team would prefer the campaign name removed from that heading as well, we will change it immediately on request.

### 5.1.1(ix) — Data collection for sensitive services
The app **does not operate a service that collects identity data**. There is no developer backend, and the developer receives none of the user's identity data. The three identity fields the user types are stored only in that user's own device Keychain and are transmitted only to `500.gov.tw`, the site where the user already holds an account, to sign that user in.

The app does contain an analytics and crash-reporting SDK (§5b). Being precise about it matters more than making it sound small, so: it is **disclosed on a blocking first-run screen and does not execute a single line until the user accepts**, after which it is **on by default and switchable off at any time**. We do not describe it as opt-in. What that SDK can receive is the part that answers this guideline: **none of the three identity fields — in any form, including hashed, truncated or concatenated — can reach it.** The transmittable surface is a set of closed Swift enums plus a content scan and an integer-range whitelist; a free-form string containing personal data does not compile, and if one were somehow constructed it would be dropped at the gate. A user who does not want it can switch it off in two taps and it stops collecting immediately. This is functionally equivalent to a password manager filling a government login form on the user's behalf. The app requests no name, no email, and no health-insurance card number, and it never asks for data that the official sign-in form does not itself require.

### 5.1.3(i) — Health data and rewards
The app **does not read health data at all** (§4): no HealthKit entitlement, no usage strings, no permission prompt, no import. Since there is no health data anywhere in the app, none can be exchanged for a benefit, and none can reach the analytics SDK.

- The record submitted to the campaign site is **a screenshot the user selects themselves from their photo library**. The app does not compose, generate, alter, or auto-fill any image.
- The set of values the telemetry layer is capable of transmitting is a closed enum (§5b). **No member of it carries a step count, a distance, an exercise duration, or any other measurement** — and the two events that previously recorded the Health-link action were removed along with the feature.
- No user property of any kind is set (`UserProperty` is an empty enum).
- The binary links no advertising identifier framework at all (`AdSupport`, `AppTrackingTransparency` and `AdServices` are all absent — verifiable with `otool -l`).
- In the App Privacy questionnaire, **Health and Fitness are both declared Not Collected** — now for the simplest possible reason: the app never obtains them.

中文：**本版完全不讀取健康資料，因此不存在「健康資料換取獎勵」的疑慮，遙測裡也沒有任何健康相關事件。**


### 5.2.2 — Third-party sites and services
The app acts **only on behalf of the individual user, on that user's own account**, using credentials the user entered themselves. It performs the same requests the user could perform manually in Safari, at human pace, with no polling, no bulk operations, no multi-account support, and no automated retry storms. It respects the site's rate limits (including the daily SMS OTP cap and resend countdown) and **never bypasses any identity verification** — household-registration checks, health-insurance-card verification and SMS OTP are all left entirely to the official site. Account registration is not performed in-app at all; the app opens the official registration page in external Safari.

### 4.2 — Minimum Functionality
The app is a native SwiftUI application, not a web wrapper. It contains no in-app browser. All screens (task dashboard, upload, redemption, per-vendor item catalogue, wallet, voucher barcode, data management) are natively rendered, and HTML from the official site is parsed into native models.

### 4.8 — Login Services
Sign-in is to the user's existing government-service account. Per 4.8, government/electronic-ID authentication is exempt from the Sign in with Apple requirement. No third-party social login is offered.

### 5.1.1(v) — Account deletion
The app does not create accounts, so there is no app account to delete. Users can permanently delete all locally stored data from within the app (**我的資料 → 「立即清除本機資料」**). The account itself lives on `500.gov.tw` and is managed there; our support page links to the official site's account management.

## 8. Contact

已填入 App Store Connect 的 **App Review Information**（2026-09-06）：

| 欄位 | 值 |
|---|---|
| Last Name / First Name | REDACTED / REDACTED |
| Phone | `+886REDACTED` |
| Email | `megshao0918@gmail.com` |

**電話為什麼寫成 +886 開頭**：使用者給的是 `09REDACTED`，但審查員可能從美國撥號，本地格式的前導 0 撥不通，所以轉成國際格式。

**Email 用 `megshao0918@gmail.com` 而不是開發者帳號的信箱**：對外文件（描述、支援頁、隱私權政策）一律用這個信箱，聯絡窗口跟著一致，審查員回信才不會落到使用者不看的地方。

---
---

# Part A-短 — 實際貼進 App Store Connect 的版本（3,975 / 4,000 字元）

> 2026-09-06 已由 API 寫入版本 1.0.0 的 `appStoreReviewDetail.notes`。
> **這是從 Part A 壓縮來的，不是另一套說法**：Part A 的每一項對外主張都保留了，被刪掉的是舉例、
> 交叉引用、以及重複的中文對照。修改前請先確認 `wc -m` 仍 ≤ 4000。
> 另外兩個 Demo Account 欄位填的是：`demoAccountName` = `A000000000`、
> `demoAccountPassword` = `1990-01-01 / 0900000000`（這個 App 沒有密碼，把生日與手機號放在這裡，
> 讓只看欄位不看 Notes 的審查員也拿得到三碼）。

```
1) WHAT THIS IS — AN UNOFFICIAL APP
Sports Rewards is an unofficial, personal-use companion app for a public exercise campaign in Taiwan ("揮汗有禮", run on 500.gov.tw). The developer is an independent individual, NOT affiliated with, endorsed by, sponsored by or authorized to represent the Ministry of Sports or any government agency. The App Store name is neutral: "Sports Rewards"; the campaign name appears only in the subtitle, immediately followed by "非官方" (unofficial). The icon carries no government emblem, agency name or "500", and the description's first paragraph says the app is unofficial. The app has no backend of its own: it is a native HTTPS client acting on the user's behalf, with credentials the user typed in, against their own account. Requests reach only 500.gov.tw; every other domain is blocked by an allowlist.

2) DEMO ACCOUNT — REQUIRED TO REVIEW
Real sign-in needs a valid Taiwan ID, date of birth and mobile number already on the government site, which a reviewer cannot obtain, so we ship a fully disclosed demo mode. Enter these in the app's sign-in form:
  身分證號 (ID) = A000000000
  出生日期 (Date of birth) = 1990-01-01
  手機號碼 (Mobile) = 0900000000
a. First launch shows a mandatory disclaimer ("使用前請先確認"): tick the checkbox, tap "同意並開始使用".
b. Tap "開始使用" on the welcome screen.
c. Type A000000000 into 身分證號.
d. Tap 出生日期. The wheel defaults to the ROC calendar; use the segmented control to switch to 西元 (Gregorian), pick 1990 / 1 / 1, tap "完成". (1990-01-01 = 民國 79 年 1 月 1 日.)
e. Type 0900000000 into 手機號碼, tap "送出並驗證".
f. Demo mode starts, with a pinned black banner "示範模式 · 畫面為範例資料，未連線官方網站". All four tabs plus upload and redeem flows work with mock data.
g. To exit: 我的資料 → 安全與隱私 → "離開示範模式".
Not a hidden feature (2.3.1): the entry point is the ordinary sign-in form, it is documented here and in the Demo Account fields, and a permanent banner announces it. A000000000 fails the official ROC ID checksum, so no real user can trigger it accidentally. In demo mode every service is a mock: no network request, no Keychain write, no telemetry event.

3) HEALTHKIT — READ-ONLY, NEVER TRANSMITTED
Read access only, for stepCount, distanceWalkingRunning and appleExerciseTime, used only to show users their own daily activity on device and whether they met the campaign threshold. Health data never leaves the device — not to the government site, not to the developer (we run no server), and never to the telemetry SDK, not even a derived boolean such as "did the user hit today's goal", which Telemetry.swift forbids per 5.1.3. There is no write path and Health access is optional. NSHealthUpdateUsageDescription exists only to satisfy upload validation ITMS-90683; the app never writes health data.

4) THIRD-PARTY SDK — FIREBASE ANALYTICS / CRASHLYTICS
One third-party SDK, for anonymous usage stats and crash reports. None of it runs until the user accepts the mandatory first-run disclaimer, which states plainly that the app sends anonymous usage records and crash reports to Google Firebase. After acceptance it is on by default, switchable off any time in 我的資料 → 安全與隱私. It never receives the ID number, date of birth or mobile number in any form, health data, uploaded screenshots, voucher codes or user-typed text. No ads, no IDFA, no tracking: the binary links neither AdSupport nor AppTrackingTransparency, so no ATT prompt appears. Ordering note: the disclaimer precedes onboarding and demo mode starts inside it, so a reviewer's device contacts Google once, at acceptance, and nothing after.

5) STORAGE AND DELETION (5.1.1(v))
Those three fields are stored encrypted in the iOS Keychain on device, not synced to iCloud, not written to log files. "我的資料 → 立即清除本機資料" deletes them permanently and resets the consent record. The campaign account itself is managed by the user at 500.gov.tw.

6) OPEN SOURCE (MIT)
https://github.com/megshao/sports_rewards_ios — see DemoMode.swift, Telemetry.swift, SportsRewardsKit/Networking and /Security.
```

# Part B — 內部備註（**不要貼給 Apple**）

## B1. 送審前必須先修掉的東西（狀態：3/3 已修）

| # | 問題 | 位置 | 狀態 |
|---|---|---|---|
| 1 | 頁尾寫 `揮汗有禮 v0.1 · 非官方工具` | `App/Sources/Views/ProfileView.swift` | ✅ **已修**：改為 `Sports Rewards v{CFBundleShortVersionString} · 非官方工具`，版本號改讀 Bundle，不再硬編碼。 |
| 2 | 首次啟動頁沒有非官方聲明 | `App/Sources/Views/WelcomeView.swift` | ✅ **已修**：歡迎頁主標為 `Sports Rewards`、圖示用 App icon、副標說明用途，並有非官方聲明卡。Part A §1 的「三處揭露」現已成立。（歡迎頁已於 v1.1 從 `OnboardingView` 拆出，並改排在免責聲明之前。） |
| 3 | App 內沒有開源 repo 連結 | 「我的資料 › 安全與隱私」 | ✅ **已修**：新增「原始碼」一列，以外部 Safari 開啟 https://github.com/megshao/sports_rewards_ios（不用 WebView）。 |

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
| 1 | ~~**帶 HealthKit entitlement 的 App 裡出現 Google SDK**~~ **已消除**：HealthKit 功能整個移除後，App 不再帶 entitlement、不再讀任何健康資料，「健康資料有沒有進 Firebase」這個問題不再成立。Part A §4 與 §7 的 5.1.3(i) 段改為主動說明「完全不使用」。 | 5.1.3(i) | 無殘餘風險。**唯一要守住的是不要把功能加回來**——一旦加回，這一列連同 `privacy-labels.md` 的 Health 格都要重寫。 |
| 2 | **隱私標籤必須與實際行為完全一致**。四格從 Not Collected 改成 Collected，任何一格填錯就是 metadata 違規（可下架）。 | 5.1.1 / 5.1.2 | 依 `docs/release/privacy-labels.md`（2026-09-06 大改版）逐格填；送審前對照 `PrivacyInfo.xcprivacy` 再核一次，兩邊不可以不一致。**Location › Coarse Location 那格仍是 `TODO(待確認)`**，送審前務必查 Google 當時的官方對照表。 |
| 3 | **「同意前 Firebase 一行程式碼都不執行」這句話必須永遠為真**。預設值改成 `true` 之後，這句話取代了舊的「預設關閉」成為本案唯一的辯護點，同時出現在 Review Notes、隱私政策、官網、商店描述與 CHANGELOG。任何人把 `DisclaimerConsent.record()` 裡的 `Telemetry.configure()` 搬到別的時機、拿掉 `configure()` 三道前置條件的任一道、或從 `DisclaimerView` 拿掉使用統計那一條揭露，這五個地方會同時變成不實陳述。 | 2.3.1 | 建議在 CI 加檢查：`DisclaimerConsent.record()` 包含 `Telemetry.configure()`、`configure()` 的三道 guard 都在、四個 Info.plist 旗標仍為 `false`，且 `DisclaimerView` 的揭露文案含「匿名使用統計」字樣，否則 fail。**目前沒有這些檢查。** |
| 4 | **送審 archive 必須含正式的 `GoogleService-Info.plist`**。它不進版控，缺檔時遙測全程 no-op——使用者打開開關也不會有任何反應。這不會被拒審，但會變成「宣稱有、實際沒有」的落差。 | — | 打包前確認 `App/Resources/GoogleService-Info.plist` 存在。已列入 `app-store-metadata.md` §11 檢查清單。 |
| 5 | **審查期間的當機收不到，但審查員的裝置仍會連一次 Google**。免責聲明擋在 Onboarding 之前，示範模式卻是在 Onboarding 的登入表單才進入的，所以審查員的實際路徑是「先同意（Firebase 於此初始化、送出 `first_open`、Installations 連線一次）→ 才進示範模式」。進入之後一個事件都不送，所以當機仍然收不到。**舊版 Review Notes 寫的「示範模式下對 Google 零連線」已經不成立，已全面改寫。** | — | 時序改不掉（示範模式也走 `finish()`，無法用 `hasCompletedOnboarding` 事先區分），除非把初始化延到真實登入成功——那會失去整個 onboarding 漏斗。**決定：不改時序，改為在 Part A §2 與 §5b 主動告知審查員**——審查員自己發現一個沒人提過的 Google 連線，比我們先講糟得多。補救方式仍是送審前自己在示範模式把全部流程跑一遍。 |
| 6 | **開源 + 公開 repo 的灌水風險**。`GoogleService-Info.plist` 雖不進版控，但 App 一上架，任何人都可以從 IPA 取出設定並灌假事件。 | — | 在 GCP 主控台**限制 API key 的 bundle ID**。`TODO(待確認：是否已設定)` |
| 7 | **預設開啟本身的曝險**：審查員實際體驗到的行為從「不碰 Google」變成「同意後就開始送」。但揭露點也從「設定頁第三層的一個開關」提升成「進 App 必經、必須主動勾選的阻斷式畫面」，這一點是變好的。 | 2.3.1 / 5.1.1 | 這不是審查問題，是**描述一致性**問題：只要商店描述、隱私標籤、隱私政策、Review Notes 四者都說「同意後預設開啟」而不是「opt-in」，就沒有 2.3.1 風險。**已全面改完。**反而要防的是日後有人把舊稿的「opt-in」字樣複貼回來。 |

## B1d. 實作與 `docs/analytics-plan.md` 的已知落差（送審前請自行決定要不要補）

`analytics-plan.md` 是設計提案，實作只落實了其中一部分。以下差異**目前不影響上面任何一句對外宣稱的真偽**，但會影響辯護力道：

| 計畫 §6.6 建議 | 實作現況 | 影響 |
|---|---|---|
| `FirebaseAutomaticScreenReportingEnabled = NO` | **未設定** | Firebase 會自動記錄 `screen_view`（SwiftUI 下多半是 hosting controller 的類別名）。這仍不含個資，但「畫面名來自封閉列舉」這句話只適用於我們自己送的事件，**不適用於 SDK 自動送的那些**。Part A §5b 已把自動事件單獨列出，沒有把它們算進封閉列舉。 |
| `FirebaseAppDelegateProxyEnabled = NO` | **未設定**（`GoogleUtilities-AppDelegateSwizzler` 確實有被連結） | 本 App 無推播，swizzling 沒有實際用途，但它存在。 |
| `FirebaseDataCollectionDefaultEnabled = NO`、`GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE` / `_AD_USER_DATA` | **未設定** | 四個旗標現在的意義是「冷啟動預設值／還沒 `configure()` 就絕不收集」，不再代表「預設關閉」。真正擋在前面的是免責聲明同意閘門；這一列仍是少了一層「全產品總開關」的保險。 |
| 關閉同意時 `Analytics.resetAnalyticsData()` + `deleteUnsentReports()`（§6.4） | ✅ **已實作**。`setUserEnabled(false)` 與 `resetPreference()` 都會呼叫 `resetCollectedData()`，重置 app instance ID 並 `deleteUnsentReports()` | 「關掉即刻停止收集、重置安裝編號、刪未送報告」這句對外文案現在完全為真。仍然為真的限制：Firebase 沒有反初始化，本次執行期間 SDK 仍在記憶體裡，要回到「一行都不跑」得等下次冷啟動。 |
| 首次啟動的同意卡片（§6.2） | ✅ **已實作**，而且比計畫建議的更強：`DisclaimerView` 是**阻斷式**、必須主動勾選的畫面，並且直接控制 `Telemetry.configure()` 的呼叫時機 | 這是現在能支持「預設開啟」的唯一理由。它的揭露文案是全案最不能動的一段。 |

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

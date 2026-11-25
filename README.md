# SOR Team Board for iPhone

**Where things stand (2026-11-25):** version 1.0 is submitted to the App Store as an unlisted app (release set to manual). Still to do after approval: Apple's reply to the unlisted request, then **Release This Version**, then share the link (apps.apple.com/app/id<Apple ID>) on Slack / the website. App Review signs in with **Other sign-in** (a Firebase Email/Password account approved as Viewer); keep that account until review is done for each version. Listing text, review notes and privacy/age-rating answers: `AppStore/metadata.md`. **1.0.1** (build 202611242243 or newer: board columns always show their tasks (paging scroll view instead of a page TabView); theme matches the iPhone by default; Create is a real tab (no glass bounce); My Work no longer shows an empty Grants column; the helper's Gemini permission card fits the half-height sheet; all-day events like competitions show on their real day, not the day before) is uploaded; submit it as a new version after 1.0 is approved.

Rules learned the hard way:
- Never animate or blur full-screen backgrounds (`AppBackground` in `Views/Theme.swift`): it ran the iPhone's display server out of memory (screen flash + spinner).
- Native screens don't change when the website does. A website feature change needs the matching change here and a new build.
- `WebLink` and anything used in release code must not be `#if DEBUG`-only (a TestFlight upload failed on that).
- The grant tracker was removed (Business is a normal board); don't re-add without asking.

A native SwiftUI app for the FRC 6059 team board. It reads and writes the same Firestore database as the website (https://team.systemoverload.org) and is governed by the same `firestore.rules`. Every write mirrors the website's document shapes, so the website, the Slack bot and the app stay in step.

- `project.yml`: the XcodeGen spec. Run `xcodegen generate` after adding or removing files; don't hand-edit `SOR.xcodeproj`
- `Config.xcconfig`: settings for the team account (Google URL scheme, Apple team ID)
- `SOR/Services/AppModel.swift`: sign-in, live listeners, permissions (`can.*`) and every write
- `SOR/Model/TeamCalendar.swift`: a port of the website's ICS reader. Meeting ids must match `mod-calendar` and the bot's `lib/calendar.mjs`
- `SOR/Services/DemoData.swift`: demo mode, with invented people only
- `PRIVACY.md`: the draft privacy policy

## Run it

```sh
brew install xcodegen   # once
xcodegen generate
open SOR.xcodeproj
```

- **Demo mode:** in Xcode, open Product › Scheme › Edit Scheme › Run › Arguments and add `-demo`. It uses invented data and never touches the database.
- **Without `-demo`:** the app runs on the **live** database, like localhost:5173.

## One-time setup

1. **Register the iOS app in Firebase.** In the Firebase console for project `frc6059-9e793`, go to Project settings › Add app › iOS, with bundle ID `org.systemoverload.team`. Download `GoogleService-Info.plist` into `SOR/`. It holds public client config, not a secret. If the file has no `CLIENT_ID`, check that Google is enabled under Authentication › Sign-in method, then download the file again.
2. **Set up Google sign-in.** Copy the plist's `REVERSED_CLIENT_ID` into `GOOGLE_REVERSED_CLIENT_ID` in `Config.xcconfig`.
3. **Signing.** Set `DEVELOPMENT_TEAM` in `Config.xcconfig` to the team ID of the account that will publish the app. The account owner adds you in App Store Connect › Users and Access (App Manager or Admin).
4. Run `xcodegen generate` again, then build.

## Test installs and releases

- `./dev-install.sh`: a 7-day test copy on your plugged-in iPhone, signed with your free Personal Team (bundle `org.systemoverload.team.dev`; no push, universal links or live widget).
- `./release.sh`: archive, cloud-sign with the App Store Connect API key (`~/.appstoreconnect/private_keys/`, never in the repo) and upload to TestFlight. The Apple account is an Individual membership, so this is the only way builds get signed from this Mac.
- `tools/make-icon.swift`: draws the app icon (`swift tools/make-icon.swift out.png`).

## Push, links, check-in, widget

- Push: the app saves each phone's FCM token to `pushTokens/{token}` (rules: you write your own, nobody reads). The Slack bot sends them (`slack-bot/lib/push.mjs` on the `slack-bot-server` branch). What people turned off: `users/{uid}.push.<kind>`; kinds match `PushKind`. Apple needs the team's APNs key uploaded in Firebase › Project settings › Cloud Messaging.
- Universal links: `applinks:team.systemoverload.org`; the site server serves `/.well-known/apple-app-site-association` (task, action, signups, checkin, agendas).
- QR check-in: VisionKit scanner → the same `checkins` + `attendance` batch as the website (`checkIn(code:)`).
- Widget: the app writes `WidgetSnapshot` to a shared keychain group (`<team>.org.systemoverload.team.shared`); the widget only reads it. Not an App Group: on the Individual account those can only be registered by the account holder.

## Before the App Store

- The website's `/privacy` page and the rules that let people delete their own `users`/`userDetails` documents must be live (both are in the SOR.github.io changes from 2026-11-24).
- Website pages inside the app sign in with `window.sorAppToken` (see `WebPageView.swift` and `onAuth` in index.html). Debug runs can use `-site http://localhost:5173`, `-tab meetings`, `-page signups`, `-openWeb analytics`.
- App Review needs a Google test account that a Board member has approved, as a viewer or member.
- Choose unlisted distribution: submit normally, then request it at developer.apple.com/contact/request/unlisted-app.

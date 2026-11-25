# SOR Team Board for iPhone

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

## Before the App Store

- The website's `/privacy` page and the rules that let people delete their own `users`/`userDetails` documents must be live (both are in the SOR.github.io changes from 2026-11-24).
- Website pages inside the app sign in with `window.sorAppToken` (see `WebPageView.swift` and `onAuth` in index.html). Debug runs can use `-site http://localhost:5173`, `-tab meetings`, `-page signups`, `-openWeb analytics`.
- App Review needs a Google test account that a Board member has approved, as a viewer or member.
- Choose unlisted distribution: submit normally, then request it at developer.apple.com/contact/request/unlisted-app.

# App Store listing: SOR Team Board (iOS 1.0)

Copy each block into App Store Connect › SOR Team Board › iOS App 1.0 (and App Information / App Privacy where noted).
**Images to upload** (all opaque PNGs):
- **iPhone screenshots:** `AppStore/screens/iPhone-6.9in/` (1320 × 2868). If App Store Connect says the size is wrong, it's asking for a different display: use `iPhone-6.9in-1290/` (1290 × 2796) for 6.9", or `iPhone-6.5in/` (1284 × 2778) / `iPhone-6.5in-1242/` (1242 × 2688) for a 6.5" slot. Drag them in the numbered order.
- **Header** (Product Page Information › Header and Search Results): `AppStore/header.png` (3840 × 1646, 21:9)
- **Search results:** `AppStore/search-results.png` (3840 × 2560, 3:2)
- **App previews (videos):** optional; none for 1.0.
- `AppStore/screenshots/` holds the raw captures (with transparency): don't upload those. `tools/make-banners.swift` redraws the header images.

---

## App Information

- **Name:** SOR Team Board
- **Subtitle** (30 max): `Tasks & meetings for FRC 6059` (29)
- **Category:** Productivity (secondary: Education)
- **Content rights:** No, it doesn't contain, show or access third-party content.
- **Age rating:** see the questionnaire answers below.

## Version information

**Promotional text** (170 max)

```
Everything System Overload Robotics runs on, in your pocket: your tasks, the meeting calendar, signups, check-in and the Board's action items.
```

**Description**

```
SOR Team Board is the team app for FRC Team 6059 System Overload Robotics: the same board the team uses on the web, built for iPhone. It's for our students, mentors, parents and Board, and a Board member approves every new account.

YOUR WORK
• Home shows what's on your plate, what's due soon, your action items and the next meeting at a glance.
• Every subteam's board: To Do, In Progress and Done. Tick a task off with one tap.
• Task details: owners and backups, due dates, checklists, comments, photos, goals and what each task is waiting on.

MEETINGS
• The team calendar by month, with where and when, and a Zoom button for online meetings.
• Signups: see who's going and whether a meeting has enough adults. Students get a link straight to the week's Slack post.
• Check in by scanning the QR code on the meeting-room screen, and see your attendance score.
• Hangar agendas, written in Slack, in one place.

LEADERSHIP
• Action items from Board, Build Committee and Operations meetings, grouped by the meeting they came from, with Slack reminders.
• The Board Room for confidential items and the Board's channel (Board and lead mentors only).
• Timeline: the season's goals as a pinboard, and a schedule of what's running late.
• Analytics: attendance and where the work is.

ALSO
• Notifications when you're put on a task, someone comments, an action item is yours, or a meeting you signed up for is an hour away.
• A Home Screen widget with the next meeting and the countdown to the next competition.
• An optional helper you can ask about the board. It asks your permission first, because it's run by Google Gemini.

New here? Tap "Look around the demo" to try the app with made-up data, no account needed.
```

**Keywords** (100 max, no spaces after commas)

```
robotics,FRC,FIRST,team,tasks,kanban,meetings,signups,attendance,check-in,action items,6059
```

- **Support URL:** https://team.systemoverload.org/support
- **Marketing URL:** https://team.systemoverload.org (optional)
- **Copyright:** `2026 System Overload Robotics`
- **Version:** 1.0 · **Build:** 202611242044 (or newer)

## App Review Information

- **Sign-in required:** yes
  - **User name:** the reviewer email you made in Firebase (Authentication › Users), e.g. `appreview@systemoverload.org`
  - **Password:** its password
- **Contact:** your name, a phone number Apple can reach, your email
- **Notes:**

```
SOR Team Board is an internal app for the members of FRC Team 6059 System Overload Robotics (a high-school robotics team): students, mentors, parents and the team's Board. We've requested unlisted distribution: only people with our link should find it.

How to sign in: on the first screen tap "Other sign-in" and use the account above. It's an approved Viewer on the team board, so it can look at everything a regular member can but can't change team data. Team members sign in with their Google accounts, and every new account has to be approved by a Board member before it can see anything.

No account needed: "Look around the demo" on the first screen opens the whole app with made-up people and data. Nothing in the demo is saved.

Features to try: Home; Tasks (each subteam's board, task details); Meetings (calendar, signups, attendance with QR check-in, agendas); You (notifications, account deletion under You › Delete my account).

The optional helper (sparkle button on Home) is run by Google Gemini. It shows what will be sent to Google and asks permission before the first message; nothing is sent until the person taps Allow.

Accounts can be deleted in the app: You › Delete my account.
```

## App Privacy (the "nutrition label")

**Do you or your third-party partners collect data from this app?** Yes.

For every type below: **Linked to the user: Yes. Used for tracking: No. Purpose: App Functionality** (only).

| Category | Type | Why |
|---|---|---|
| Contact Info | Name | Shown to the team on tasks, signups and attendance |
| Contact Info | Email Address | Sign-in, and approving new accounts |
| User Content | Photos or Videos | Photos people add to tasks (kept 14 days) |
| User Content | Other User Content | Tasks, comments, action items, check-ins, helper messages |
| Identifiers | User ID | The account's ID in the team database |
| Identifiers | Device ID | The push-notification token for this phone |
| Sensitive Info | Sensitive Info | Optional answer to "Do you identify as female?" (used to make sure meetings have the right adults; only the person and team leads can see it) |

Not collected: location, health, financial info, contacts, browsing or search history, purchases, usage data, diagnostics, advertising data.

**Privacy Policy URL:** https://team.systemoverload.org/privacy

## Age rating questionnaire

Answer "None" to every content category (violence, sexual content, profanity, horror, drugs, alcohol, gambling, contests, medical). Then:

- **Unrestricted web access:** No. It only opens the team's own website pages and links people post.
- **User-generated content:** Yes. Team members post tasks, comments and photos, but only to their own approved team; there's no public sharing or contact with strangers.
- **Messaging and chat:** Yes, limited to the team (comments, the Board channel).
- **AI-generated content / chatbot:** Yes. An optional helper (Google Gemini) answers questions about the board, after the person agrees.
- **Made for Kids:** No.

That usually comes out at **13+**. Our members are high-school students, so that fits.

## Pricing and Availability

- **Price:** Free
- **Availability:** United States only
- **Unlisted:** submit https://developer.apple.com/contact/request/unlisted-app with the app's Apple ID (App Store Connect › App Information › Apple ID) around the time you submit for review.

## Before you press Submit

- [ ] The reviewer account exists in Firebase, has signed in once in the app, and is approved as **Viewer**
- [ ] Email/Password is turned on in Firebase › Authentication › Sign-in method
- [ ] Build 202611242044 or newer is selected
- [ ] Only the **iOS** version is submitted (leave macOS 1.0 alone)

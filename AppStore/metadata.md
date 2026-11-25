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
- **Version:** 1.0.1 · **Build:** 202611251159 (or newer)

## App Review Information

Rejected 2026-11-25 under 2.1 (Information Needed): Apple wants a screen recording plus answers to six questions in the Notes. Resubmit with:

- **Version:** rename the App Store version from 1.0 to **1.0.1** (the Version field on the version page), then pick build **202611251159** or newer.
- **Sign-in required:** yes, two Other sign-in accounts (Firebase › Authentication › Users, both approved as Viewer): one to look around, one Apple can delete.
- **Attachment:** the screen recording (App Review Information › Attachment).

### Screen recording (on your iPhone, latest iOS, TestFlight build 202611251159)

Control Center › Screen Recording, then, in one take (2–4 minutes):
1. Start on the Home Screen and open SOR Team (launch must be in the recording).
2. Sign-in screen: point at the Community Rules line, then **Other sign-in** with the second review account.
3. Home: stats, the next meeting, the competition countdown.
4. Tasks › a board › a task: details, comments, photos.
5. Long-press a comment › **Report** › pick a reason › Send. Long-press again › **Block**, show the comment disappear. You › Blocked people › Unblock.
6. Meetings: calendar, signups, attendance.
7. The sparkle button: the helper's Gemini permission screen (Allow, ask one question).
8. You › Reports (needs an admin account: either show it from your own account in a second short clip, or skip it).
9. You › **Delete my account** › confirm. It returns to the sign-in screen.

### Notes (paste into App Review Information › Notes)

```
1. SCREEN RECORDING
Attached. Recorded on an iPhone running the latest iOS with this build: launch, sign-in, the main screens, reporting and blocking, the AI helper's permission screen, and account deletion.

2. PURPOSE AND AUDIENCE
SOR Team Board is the internal app for FRC Team 6059 System Overload Robotics, a high-school robotics team (about 40 students plus mentors, parents and a student/parent Board). It replaces spreadsheets and scattered Slack threads: each subteam's task board, the meeting calendar, meeting signups, QR check-in and attendance scores, and the Board's action items, in one place that matches the team's website (team.systemoverload.org). It is only useful to members of this team, so we have requested unlisted distribution.

3. HOW TO ACCESS IT
On the first screen tap "Other sign-in" and use either account below. Both are approved Viewers: they can see everything a regular member sees but can't change team data. Please use the second account to try account deletion (You > Delete my account); the first stays for future reviews.
  Account 1: <email 1> / <password 1>
  Account 2: <email 2> / <password 2>
No account needed: "Look around the demo" on the first screen opens the whole app with made-up people and data; nothing is saved.
Team members sign in with Google, and every new account must be approved by a Board member before it can see anything. Main features: Home; Tasks (each subteam's board and task details); Meetings (calendar, signups, attendance, QR check-in); You (notifications, report/block, account deletion).

USER CONTENT AND SAFETY
Members can write task comments, add task photos and post in the Board's private channel, only inside their approved team. Everyone agrees to the team's Community Rules on the sign-in screen (no objectionable content or abuse; team.systemoverload.org/support#rules). Long-press any comment, photo or message to Report it or Block its author; tasks have "Report this task". Reports go to the team's admins (the Board and lead mentors), who review them within 24 hours in You > Reports and can remove the content and remove the person from the team. Blocking hides that person's content immediately. Contact: arnanbajaj@gmail.com.

4. EXTERNAL SERVICES
- Google Firebase: Authentication (Google and email sign-in), Cloud Firestore (the team's database), Cloud Messaging (notifications, delivered through Apple Push Notification service).
- Google Sign-In.
- Google Gemini: the optional helper, called through the team's own server. It asks permission before anything is sent.
- The team's own server (team.systemoverload.org): the website, privacy policy, support page and the helper's connection to Gemini.
- Google Calendar and Slack feed the team's calendar and signups into the database on the server side; the app doesn't connect to them directly.
No payments, ads, analytics or tracking.

5. REGIONS
The app works the same everywhere; there are no regional differences. It's offered in the United States, where the team is.

6. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. The app isn't in a regulated industry and shows only the team's own content.
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

import Foundation

/// Invented people and work for demo mode (launch argument `-demo`). Never real team members.
extension AppModel {
    func startDemo() {
        demo = true
        uid = "demo-you"
        authName = "Alex Rivera"
        authEmail = "alex@example.com"
        profile = Person(id: uid, ["name": "Alex Rivera", "email": "alex@example.com", "role": "admin", "memberType": "board", "subteamIds": ["prog"], "onboardedAt": 1])

        let people: [(String, String, String)] = [
            ("demo-you", "Alex Rivera", "lead"), ("u-sam", "Sam Okafor", "member"), ("u-maya", "Maya Chen", "member"),
            ("u-jordan", "Jordan Patel", "member"), ("u-priya", "Priya Nair", "lead"), ("u-leo", "Leo Martins", "member"),
        ]
        users = people.map { Person(id: $0.0, ["name": $0.1, "email": "\($0.0)@example.com", "role": $0.2, "onboardedAt": 1]) }

        let teams: [(String, String, String)] = [
            ("prog", "Programming", "#34C759"), ("elec", "Electrical", "#FFCC00"), ("vision", "Vision", "#A2845E"),
            ("cad", "Design", "#007AFF"), ("mech", "Manufacturing", "#FF9500"), ("biz", "Business", "#AF52DE"), ("media", "Outreach", "#FF2D55"),
        ]
        subteams = teams.enumerated().map { i, t in Subteam(id: t.0, ["name": t.1, "color": t.2, "position": Double(i)]) }
        columns = [("todo", "To Do", 0.0), ("doing", "In Progress", 1.0), ("done", "Done", 2.0)].map { BoardColumn(id: $0.0, ["name": $0.1, "position": $0.2]) }
            + [BoardColumn(id: "grants", ["name": "Grants", "position": -1.0, "subteamIds": ["biz"]])]
        grants = [
            Grant(id: "gr1", ["name": "Example Robotics Foundation", "amount": "$5,000", "deadline": Day.iso(Date().addingTimeInterval(5 * 86400)), "status": "in-progress", "writer": "Maya Chen", "writerUid": "u-maya"]),
            Grant(id: "gr2", ["name": "Springfield Community Fund", "amount": "up to $2,500", "deadline": "rolling", "status": "not-started"]),
            Grant(id: "gr3", ["name": "Valley Tech Sponsorship", "amount": "$1,000", "wonAmount": "$1,000", "status": "won"]),
        ]
        teamReminders = [TeamReminder(id: "n1", ["text": "Bring the budget draft to the Board meeting", "track": "board", "date": Day.iso(Date().addingTimeInterval(2 * 86400)), "time": "16:00",
                                                 "sendAt": (Date().addingTimeInterval(2 * 86400).timeIntervalSince1970 * 1000), "createdBy": "demo-you"])]

        let day = { (n: Int) in Day.iso(Date().addingTimeInterval(Double(n) * 86400)) }
        let seed: [(String, String, String, [String], Int?, String, [(String, Bool)])] = [
            ("Tune swerve PID on the practice bot", "prog", "doing", ["demo-you", "u-sam"], 2, "high", [("Log module angles", true), ("Retune drive kP", false), ("Test on carpet", false)]),
            ("Auto path for the 3-piece routine", "prog", "todo", ["demo-you"], 6, "med", []),
            ("Vision pose estimate into odometry", "vision", "doing", ["u-maya", "demo-you"], -1, "critical", []),
            ("Wire the new CANivore bus", "elec", "todo", ["u-jordan"], 4, "med", [("Crimp connectors", false)]),
            ("Intake roller v3 in CAD", "cad", "doing", ["u-priya"], 9, "med", []),
            ("Cut gussets on the router", "mech", "todo", ["u-leo"], 3, "low", []),
            ("Sponsor thank-you letters", "biz", "todo", ["demo-you"], 12, "med", []),
            ("Robot reveal video", "media", "todo", [], nil, "med", []),
            ("Bench test the climber", "mech", "done", ["u-leo", "demo-you"], -3, "med", []),
        ]
        var docs: [String: Doc] = [:]
        for (i, s) in seed.enumerated() {
            docs["t\(i)"] = [
                "title": s.0, "subteamId": s.1, "columnId": s.2, "assigneeUids": s.3, "dueDate": s.4.map(day) ?? "",
                "priority": s.5, "checklist": s.6.map { ["text": $0.0, "done": $0.1] as Doc }, "position": Double(i * 1000),
                "createdBy": "demo-you", "createdAt": 0, "commentCount": i == 0 ? 1 : 0,
            ]
        }
        // A team goal made of three of those tasks, and a subteam priority
        docs["g1"] = ["title": "Drivetrain ready for week 0", "subteamId": "goals", "columnId": "doing", "isGoal": true, "childIds": ["t0", "t3", "t8"],
                      "dueDate": day(10), "priority": "high", "position": 0.0, "createdBy": "demo-you", "createdAt": 0]
        docs["g2"] = ["title": "Sponsor packet sent", "subteamId": "biz", "columnId": "todo", "isGoal": true, "childIds": ["t6"],
                      "dueDate": day(16), "priority": "med", "position": 1.0, "createdBy": "demo-you", "createdAt": 0]
        demoDocs = docs
        demoComments["t0"] = [Comment(id: "c1", ["authorId": "u-sam", "body": "Drive kP feels high on carpet. Let's try 0.04 after school.", "createdAt": Double(nowMs - 3_600_000)])]
        allTasks = docs.map { TaskItem(id: $0.key, $0.value) }

        settings = ["calendar": ["ics": Self.demoICS()], "leadership": ["boardEmails": ["alex@example.com"]]]
        let now = Double(nowMs)
        boardChannel = [
            ChannelMessage(id: "m1", ["text": "Kickoff venue: the library said yes for the 9th.", "authorId": "u-priya", "authorName": "Priya Nair", "createdAt": now - 86_400_000]),
            ChannelMessage(id: "m2", ["text": "Great. I'll put it on the calendar tonight.", "authorId": "demo-you", "authorName": "Alex Rivera", "createdAt": now - 80_000_000]),
        ]
        boardAgendaDocs = [AgendaDoc(id: "bd1", ["track": "board", "date": day(3), "startTime": "17:30", "items": [
            ["topic": "Action items check-in", "points": "Review open items\nMeeting recap", "who": "All", "minutes": 20, "urgency": "high"],
            ["topic": "Kickoff plans", "points": "Venue, food, schedule", "who": "Board", "minutes": 15, "urgency": "medium"]] as [Doc]])]
        actionItems = [
            ActionItem(id: "a1", ["text": "Confirm the kickoff venue", "ownerUids": ["demo-you"], "dueDate": day(4), "track": "board", "assignedOn": day(-2), "seasonId": Season.home]),
            ActionItem(id: "a2", ["text": "Order the spare swerve modules", "ownerUids": ["u-jordan", "demo-you"], "dueDate": day(7), "track": "build", "assignedOn": day(-1), "seasonId": Season.home]),
        ]
        privateActionItems = [ActionItem(id: "p1", ["text": "Draft next year's budget", "ownerUids": ["demo-you"], "dueDate": day(12), "track": "board", "assignedOn": day(-2), "seasonId": Season.home], confidential: true)]
        roster = [("r1", "Alex Rivera", "student", "demo-you"), ("r2", "Sam Okafor", "student", "u-sam"), ("r3", "Casey Brooks", "student", ""),
                  ("r4", "Dana Brooks", "parent", ""), ("r5", "Morgan Lee", "mentor", "")].map {
            RosterPerson(id: $0.0, ["name": $0.1, "kind": $0.2, "uid": $0.3, "female": $0.0 == "r4"])
        }
        let names = [("demo-you", "Alex Rivera"), ("u-sam", "Sam Okafor"), ("u-maya", "Maya Chen"), ("u-jordan", "Jordan Patel"), ("u-leo", "Leo Martins")]
        teamMarks = (0..<8).flatMap { w in names.enumerated().compactMap { i, n -> Mark? in
            let st = (w + i) % 5 == 0 ? "partial" : (w * i) % 7 == 3 ? "unexcused" : "present"
            return Mark(id: "mk\(w)\(i)", ["meetingId": "demo-\(w)", "date": day(-7 * (8 - w)), "title": "Hangar Build Session", "uid": n.0, "name": n.1, "kind": "student", "status": st])
        } }
        events = TeamCalendar.events(fromICS: Self.demoICS())
        loaded = ["users", "subteams", "columns", "tasks", "settings", "calendar", "actionItems", "privateActionItems", "boardChannel", "teamAttendance", "signups", "attendance", "agendas", "roster", "grants", "teamReminders", "grantAnswers", "grantInfo"]
        phase = .ready
        updateWidget()
    }

    /// A small ICS feed relative to today, so the real parser and repeat rules run in the demo.
    static func demoICS() -> String {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        func stamp(_ d: Date, _ h: Int, _ m: Int = 0) -> String {
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d%02d%02dT%02d%02d00", c.year!, c.month!, c.day!, h, m)
        }
        func dateOnly(_ d: Date) -> String {
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
        }
        let now = cal.component(.hour, from: Date())
        let weekday = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][cal.component(.weekday, from: today) - 1]
        let comp = today.addingTimeInterval(23 * 86400)
        return """
        BEGIN:VCALENDAR
        X-WR-CALNAME:SOR Team Calendar
        X-WR-TIMEZONE:America/Los_Angeles
        BEGIN:VEVENT
        UID:demo-hangar@example.com
        DTSTART;TZID=America/Los_Angeles:\(stamp(today, max(0, now - 1)))
        DTEND;TZID=America/Los_Angeles:\(stamp(today, min(23, now + 2)))
        RRULE:FREQ=WEEKLY;BYDAY=\(weekday)
        SUMMARY:Hangar Build Session
        LOCATION:Example Hangar, 100 Airport Way, Springfield, CA 94000, USA
        END:VEVENT
        BEGIN:VEVENT
        UID:demo-ops@example.com
        DTSTART;TZID=America/Los_Angeles:\(stamp(today.addingTimeInterval(2 * 86400), 19))
        DTEND;TZID=America/Los_Angeles:\(stamp(today.addingTimeInterval(2 * 86400), 20))
        RRULE:FREQ=WEEKLY;INTERVAL=2
        SUMMARY:Operations Meeting
        LOCATION:https://zoom.us/j/12345678901
        END:VEVENT
        BEGIN:VEVENT
        UID:demo-comp@example.com
        DTSTART;VALUE=DATE:\(dateOnly(comp))
        DTEND;VALUE=DATE:\(dateOnly(comp.addingTimeInterval(3 * 86400)))
        SUMMARY:Valley Robotics Showdown
        LOCATION:Example Arena, Springfield, CA
        END:VEVENT
        END:VCALENDAR
        """
    }
}

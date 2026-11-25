import SwiftUI

/// Meetings: Calendar, Signups, Attendance and Agendas, the same four pages as the website's Meetings tab.
struct MeetingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case calendar = "Calendar", signups = "Signups", attendance = "Attendance", agendas = "Agendas"
        var id: String { rawValue }
    }
    @Environment(AppModel.self) private var model
    @State private var page: Page = .calendar
    @State private var open: CalEvent?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Page", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.bottom, 8)
                switch page {
                case .calendar: CalendarPage(open: $open)
                case .signups: SignupsPage(open: $open)
                case .attendance: AttendancePage()
                case .agendas: AgendasPage()
                }
            }
            .appBackground()
            .navigationTitle("Meetings")
            .navigationDestination(for: Agenda.self) { AgendaDetailView(agenda: $0) }
            .navigationDestination(for: YouPage.self) { _ in AnalyticsView() }
            .navigationDestination(for: WebLink.self) { WebPageView(title: $0.title, path: $0.path) }
            .navigationDestination(for: TaskItem.self) { TaskDetailView(taskId: $0.id) }
            .sheet(item: $open) { MeetingDetailView(event: $0) }
            #if DEBUG
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-page"), i + 1 < args.count, let p = Page.allCases.first(where: { $0.rawValue.lowercased() == args[i + 1] }) { page = p }
            }
            #endif
        }
    }
}

/// A website page to open inside the app.
struct WebLink: Hashable {
    let title: String
    let path: String
}

// MARK: - Calendar

/// A month at a glance; tap a day for its meetings.
struct CalendarPage: View {
    @Environment(AppModel.self) private var model
    @Binding var open: CalEvent?
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var selected = Day.iso()

    private var cal: Calendar { Calendar.current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                monthGrid
                let list = model.events.filter { $0.dayKey == selected || ($0.allDay && covers($0, selected)) }
                Text(dayHeading(selected)).font(.headline).padding(.top, 4)
                if !model.loaded.contains("calendar") { SkeletonRows(count: 2) }
                else if list.isEmpty { Text("Nothing on the calendar.").foregroundStyle(.secondary) }
                ForEach(list) { e in
                    Button { open = e } label: { MeetingRow(event: e) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .refreshable { model.refreshCalendar(force: true) }
    }

    private func covers(_ e: CalEvent, _ day: String) -> Bool {
        guard let d = Day.date(day) else { return false }
        let ms = d.timeIntervalSince1970 * 1000
        // all-day events are stored at UTC midnight: compare by day keys
        let last = Day.iso(Date(timeIntervalSince1970: (e.end - TeamCalendar.day) / 1000 + 43200))
        return e.dayKey <= day && day <= last && ms >= 0
    }

    private func dayHeading(_ iso: String) -> String {
        guard let d = Day.date(iso) else { return iso }
        let n = Day.until(iso) ?? 99
        let date = d.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return n == 0 ? "Today · \(date)" : n == 1 ? "Tomorrow · \(date)" : date
    }

    private var monthGrid: some View {
        let first = month
        let days = cal.range(of: .day, in: .month, for: first)!.count
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let byDay = Dictionary(grouping: model.events, by: \.dayKey)
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return Card {
            HStack {
                Text(first.formatted(.dateTime.month(.wide).year())).font(.title3.weight(.semibold))
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.padding(.horizontal, 8)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { i in Text(ordered[i]).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(1...days, id: \.self) { d in
                    let date = cal.date(byAdding: .day, value: d - 1, to: first)!
                    let iso = Day.iso(date)
                    let evs = byDay[iso] ?? []
                    let isSel = iso == selected, isToday = iso == Day.iso()
                    Button { selected = iso } label: {
                        VStack(spacing: 3) {
                            Text("\(d)").font(.callout.weight(isToday || isSel ? .bold : .regular)).monospacedDigit()
                                .foregroundStyle(isSel ? .white : isToday ? Color.accentColor : .primary)
                            HStack(spacing: 2) {
                                ForEach(evs.prefix(3)) { e in Circle().fill(isSel ? .white : kindColor(e)).frame(width: 4, height: 4) }
                            }
                            .frame(height: 4)
                        }
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(isSel ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) { month = cal.date(byAdding: .month, value: n, to: month)! }
    }
}

func kindColor(_ e: CalEvent) -> Color {
    if e.isCompetition { return .red }
    if e.isHangar { return .orange }
    switch e.track {
    case "board": return .cyan
    case "build": return .teal
    case "ops": return .purple
    default: return .blue
    }
}

// MARK: - Signups

struct SignupsPage: View {
    @Environment(AppModel.self) private var model
    @Binding var open: CalEvent?
    @State private var weeks = 4

    var body: some View {
        let shifts = model.upcomingShifts(weeks: weeks)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text(model.signsUpInApp ? "Tap a meeting to volunteer, and see if it has enough adults."
                                        : "Students sign up in Slack: react to the week's post in #meeting-signups. It shows up here right away.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !model.loaded.contains("calendar") || !model.loaded.contains("signups") { SkeletonRows(count: 5) }
                ForEach(shifts) { sh in
                    Button { if let e = sh.event { open = e } } label: { SignupRow(shift: sh) }.buttonStyle(.plain)
                }
                if model.loaded.contains("calendar") {
                    Button("Show more") { weeks += 4 }.frame(maxWidth: .infinity).padding(.top, 6)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .refreshable { model.refreshCalendar(force: true) }
    }
}

struct SignupRow: View {
    @Environment(AppModel.self) private var model
    let shift: Shift
    var body: some View {
        let list = model.signups(for: shift.id)
        let cover = model.coverage(shift, list)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shift.title).font(.body.weight(.medium)).strikethrough(shift.cancelled)
                    Text("\(Day.pretty(shift.date)) · \(shift.event?.whenLabel ?? "")").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if shift.cancelled { Pill(text: "Cancelled", tint: .red) }
                else if model.amGoing(shift.id) { Pill(text: "Going", systemImage: "checkmark", tint: .green) }
            }
            HStack(spacing: 8) {
                if list.isEmpty { Text("No one yet").font(.caption).foregroundStyle(.secondary) }
                else {
                    AvatarStack(ids: list.prefix(6).map(\.uid), size: 20)
                    Text("\(list.count) going").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !shift.cancelled && !cover.ok { Pill(text: cover.label, tint: .orange) }
            }
        }
        .padding(12)
        .glass(16)
        .contentShape(Rectangle())
    }
}

// MARK: - Attendance

struct AttendancePage: View {
    @Environment(AppModel.self) private var model
    @State private var checkingIn = false

    var body: some View {
        let s = model.myScore
        let marks = model.mySeasonMarks
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    Text("Your score · \(model.currentSeason.name)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    Text(s.score.formatted(.number.precision(.fractionLength(0...2)))).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    HStack(spacing: 8) {
                        Pill(text: "\(s.present) present", tint: .green)
                        if s.partial > 0 { Pill(text: "\(s.partial) partial", tint: .yellow) }
                        if s.excused > 0 { Pill(text: "\(s.excused) excused", tint: .blue) }
                        if s.unexcused > 0 { Pill(text: "\(s.unexcused) unexcused", tint: .red) }
                    }
                    Text("Present counts 1, Partial ½, online shifts a third, like the team's sheet.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button { checkingIn = true } label: {
                        Label("Check in", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity).frame(height: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                }
                if model.isLead {
                    Card {
                        Text("For leads").font(.headline)
                        NavigationLink(value: WebLink(title: "Take Attendance", path: "attendance")) {
                            Label("Take attendance, students grid and roster", systemImage: "checklist")
                        }
                        NavigationLink(value: YouPage.analytics) {
                            Label("Analytics", systemImage: "chart.bar.xaxis")
                        }
                    }
                }
                SectionTitle(text: "Your meetings")
                if !model.loaded.contains("attendance") { SkeletonRows(count: 3) }
                else if marks.isEmpty { Text("No marks yet this season.").foregroundStyle(.secondary) }
                ForEach(marks) { m in
                    let st = MarkStatus(rawValue: m.status)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title.isEmpty ? "Meeting" : m.title).font(.body.weight(.medium))
                            Text(Day.date(m.date)?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? m.date).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let st { Pill(text: st.label, tint: st.tint) }
                    }
                    .padding(12)
                    .glass(16)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .sheet(isPresented: $checkingIn) { CheckInSheet() }
    }
}

// MARK: - Agendas

struct AgendasPage: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let list = model.seasonAgendas
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("What's planned for each hangar meeting. Agendas are written in Slack (#meeting-agendas) and copied here.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !model.loaded.contains("agendas") && !model.demo { SkeletonRows(count: 4) }
                else if list.isEmpty { Text("No agendas yet this season.").foregroundStyle(.secondary).padding(.top, 20) }
                ForEach(list) { a in
                    NavigationLink(value: a) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(a.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                            FlowLayout(spacing: 8, lineSpacing: 2) {
                                Text(Day.pretty(a.date))
                                ForEach(a.subteamIds.compactMap { model.subteam($0) }) { s in
                                    HStack(spacing: 4) { SubteamDot(color: s.color, size: 7); Text(s.name) }
                                }
                                if !a.authorName.isEmpty { Text("· \(a.authorName)") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            Text(AgendaText.plain(a.body)).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .glass(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .onAppear { model.wantAgendas() }
    }
}

/// Slack's formatting made readable: <url|label> links, *bold*, &amp; and friends.
enum AgendaText {
    static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"<(https?://[^|>\s]+)\|([^>]*)>"#, with: "$2", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<(https?://[^>\s]+)>"#, with: "$1", options: .regularExpression)
        return t.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }
    static func attributed(_ s: String) -> AttributedString {
        var md = s.replacingOccurrences(of: #"<(https?://[^|>\s]+)\|([^>]*)>"#, with: "[$2]($1)", options: .regularExpression)
        md = md.replacingOccurrences(of: #"<(https?://[^>\s]+)>"#, with: "[$1]($1)", options: .regularExpression)
        md = md.replacingOccurrences(of: #"(^|[\s(])\*([^*\n]+)\*"#, with: "$1**$2**", options: .regularExpression)
        md = md.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
        return (try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(plain(s))
    }
}

struct AgendaDetailView: View {
    @Environment(AppModel.self) private var model
    let agenda: Agenda
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(agenda.title).font(.title2.weight(.bold))
                    Text([Day.pretty(agenda.date), agenda.authorName].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
                }
            }
            Section { Text(AgendaText.attributed(agenda.body)).textSelection(.enabled) }
            let tasks = agenda.taskIds.compactMap { model.task($0) }
            if !tasks.isEmpty {
                Section("Tasks") {
                    ForEach(tasks) { t in NavigationLink(value: t) { Text(t.title) } }
                }
            }
            if let url = URL(string: agenda.permalink), !agenda.permalink.isEmpty {
                Section { Link(destination: url) { Label("Open in Slack", systemImage: "number") } }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Rows and the meeting sheet

struct MeetingRow: View {
    @Environment(AppModel.self) private var model
    let event: CalEvent

    var body: some View {
        let cancelled = model.isCancelled(event)
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(event.startDate.formatted(.dateTime.month(.abbreviated))).font(.caption2.weight(.semibold)).foregroundStyle(kindColor(event)).textCase(.uppercase)
                Text(event.startDate.formatted(.dateTime.day())).font(.title3.weight(.bold)).monospacedDigit()
            }
            .frame(width: 44, height: 48)
            .background(kindColor(event).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.body.weight(.medium)).strikethrough(cancelled).lineLimit(2)
                HStack(spacing: 6) {
                    Text(event.whenLabel)
                    if !event.place.isEmpty { Text("·"); Text(event.shortPlace).lineLimit(1) } else if !event.service.isEmpty { Text("·"); Text(event.service) }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if cancelled { Pill(text: "Cancelled", tint: .red) }
            else if model.amGoing(event.id) { Pill(text: "Going", systemImage: "checkmark", tint: .green) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(16)
        .contentShape(Rectangle())
    }
}

struct MeetingDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let event: CalEvent
    @State private var busy = false
    @State private var addingPeople = false

    var body: some View {
        let sh = model.shift(event.id)
        let list = model.signups(for: event.id)
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title).font(.title2.weight(.bold))
                        Text(event.allDay ? event.whenLabel : "\(event.startDate.formatted(.dateTime.weekday(.wide).month().day())) · \(event.whenLabel)")
                            .foregroundStyle(.secondary)
                        if model.isCancelled(event) {
                            Pill(text: "Cancelled\(cancelReason)", systemImage: "xmark", tint: .red).padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !event.place.isEmpty {
                    Section("Where") {
                        Button {
                            openURL(URL(string: "maps://?q=\(event.place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!)
                        } label: {
                            Label { Text(event.place).foregroundStyle(.primary) } icon: { Image(systemName: "mappin.and.ellipse") }
                        }
                    }
                }
                if let url = URL(string: event.link), !event.link.isEmpty {
                    Section("Online") {
                        Link(destination: url) { Label("Join on \(event.service)", systemImage: "video.fill") }
                        if !event.code.isEmpty { Text(event.code).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                }
                Section {
                    signupAction(sh)
                    if let sh, !sh.cancelled {
                        let c = model.coverage(sh, list)
                        if !c.ok { Label(c.label, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    }
                } header: { Text("Signing up") }
                if !list.isEmpty {
                    people("Adults", list.filter(\.isAdult))
                    people("Leadership", list.filter { !$0.isAdult && $0.leader })
                    people("Students", list.filter { !$0.isAdult && !$0.leader })
                }
                if !event.description.isEmpty {
                    Section("Details") { Text(event.description).textSelection(.enabled) }
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: WebLink.self) { WebPageView(title: $0.title, path: $0.path) }
            .sheet(isPresented: $addingPeople) { if let sh { AddPeopleView(shift: sh) } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private func people(_ title: String, _ rows: [Signup]) -> some View {
        if !rows.isEmpty {
            Section("\(title) · \(rows.count)") {
                ForEach(rows) { s in
                    HStack(spacing: 10) {
                        PersonAvatar(id: s.uid, size: 28)
                        Text(model.person(s.uid)?.name ?? s.name)
                        if s.femaleAdult { Text("F").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
                    }
                    .swipeActions {
                        if model.isLead { Button("Remove", role: .destructive) { model.removeSignup(s) } }
                    }
                }
            }
        }
    }

    private var cancelReason: String {
        let r = model.meetingExtras[event.id]?.str("cancelReason") ?? ""
        return r.isEmpty ? "" : ": \(r)"
    }

    /// Students sign up in Slack (the bot copies it to the board); parents and mentors sign up right here.
    @ViewBuilder private func signupAction(_ sh: Shift?) -> some View {
        if sh?.cancelled == true {
            Text("This meeting is cancelled.").foregroundStyle(.secondary)
        } else if model.signsUpInApp, let sh {
            Button {
                busy = true
                Task { await model.toggleSignup(sh); busy = false }
            } label: {
                HStack {
                    Label(model.amGoing(sh.id) ? "You're volunteering" : "I'll volunteer", systemImage: model.amGoing(sh.id) ? "checkmark.circle.fill" : "hand.raised.fill")
                    Spacer()
                    if busy { ProgressView() } else if model.amGoing(sh.id) { Text("Undo").foregroundStyle(.secondary) }
                }
            }
            .disabled(busy)
        } else if model.amGoing(event.id) {
            Label("You're going", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else if let url = model.slackSignupURL(event.id) {
            Link(destination: url) { Label("Sign up on Slack", systemImage: "hand.raised.fill") }
            Text("Opens this meeting's post in #meeting-signups. React to sign up.").font(.footnote).foregroundStyle(.secondary)
        } else {
            Text("Not posted in Slack yet").foregroundStyle(.secondary)
        }
        if model.isLead, let sh, !sh.cancelled {
            Button { addingPeople = true } label: { Label("Add someone", systemImage: "person.badge.plus") }
        }
    }
}

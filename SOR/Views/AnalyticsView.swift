import SwiftUI
import Charts

/// Analytics: how the team is doing, worked out live. Students (attendance scores), Tasks (where the work is).
struct AnalyticsView: View {
    enum Tab: String, CaseIterable { case students = "Students", tasks = "Tasks" }
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .students

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Show", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented)
                if tab == .students { students } else { tasks }
            }
            .padding(.horizontal, 16).padding(.bottom, 28)
        }
        .appBackground(Brand.teal)
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.wantTeamAttendance()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-analyticsTasks") { tab = .tasks }
            #endif
        }
    }

    // MARK: Students

    @ViewBuilder private var students: some View {
        let rows = model.leaderboard
        if !model.loaded.contains("teamAttendance") && !model.demo {
            SkeletonRows(count: 5)
        } else if rows.isEmpty {
            Text("No attendance marked yet this season.").foregroundStyle(.secondary)
        } else {
            let scores = rows.map(\.score.score)
            let avg = scores.reduce(0, +) / Double(scores.count)
            HStack(spacing: 10) {
                StatTile(value: "\(rows.count)", label: "Students", systemImage: "person.3.fill", color: Brand.blue)
                StatTile(value: avg.formatted(.number.precision(.fractionLength(1))), label: "Average score", systemImage: "chart.bar.fill", color: Brand.teal)
                StatTile(value: "\(rows.map(\.score.unexcused).reduce(0, +))", label: "Unexcused", systemImage: "xmark.circle.fill", color: .red)
            }
            weekly
            VStack(alignment: .leading, spacing: 10) {
                Text("Scores").font(.headline)
                // Plain rows, not Swift Charts: its name axis drew the names on top of the bars on a phone.
                let top = Array(rows.prefix(15))
                let best = max(top.map(\.score.score).max() ?? 1, 0.01)
                VStack(spacing: 8) {
                    ForEach(top) { r in
                        let mine = r.uid == model.uid
                        HStack(spacing: 10) {
                            Text(r.name.split(separator: " ").first.map(String.init) ?? r.name)
                                .font(.caption.weight(mine ? .bold : .regular)).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.7).frame(width: 76, alignment: .leading)
                            GeometryReader { g in
                                Capsule().fill(Brand.wash(mine ? Brand.amber : Brand.teal))
                                    .frame(width: max(4, g.size.width * r.score.score / best), height: 12)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: 16)
                            Text(r.score.score.formatted(.number.precision(.fractionLength(0...2))))
                                .font(.caption.weight(.semibold)).monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(16).glass(22)
            VStack(alignment: .leading, spacing: 0) {
                Text("Leaderboard").font(.headline).padding(.bottom, 8)
                ForEach(rows) { r in
                    HStack(spacing: 12) {
                        Text("\(r.place)").font(.subheadline.weight(.bold)).monospacedDigit().frame(width: 26)
                            .foregroundStyle(r.place <= 3 ? [Color.yellow, .gray, .orange][r.place - 1] : .secondary)
                        PersonAvatar(id: r.uid, size: 28)
                        Text(r.name).font(.subheadline.weight(r.uid == model.uid ? .bold : .regular))
                        Spacer()
                        if r.score.unexcused > 0 { Text("\(r.score.unexcused)A").font(.caption.weight(.semibold)).foregroundStyle(.red) }
                        Text(r.score.score.formatted(.number.precision(.fractionLength(0...2)))).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .padding(.vertical, 7)
                    if r.id != rows.last?.id { Divider().opacity(0.4) }
                }
            }
            .padding(16).glass(22)
            Text("Present counts 1, Partial ½, online a third; only counted meetings score, and the Board isn't ranked. The full grid and roster are on Meetings › Attendance.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// Present or partial marks per week, the whole team.
    private var weekly: some View {
        let cal = Calendar.current
        let marks = model.teamMarks.filter { ["present", "partial"].contains($0.status) && $0.date >= model.seasonFrom && !["parent", "mentor"].contains($0.kind) }
        let byWeek = Dictionary(grouping: marks) { m -> Date in
            let d = Day.date(m.date) ?? Date()
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? d
        }
        let points = byWeek.map { (week: $0.key, count: $0.value.count) }.sorted { $0.week < $1.week }.suffix(12)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Check-ins by week").font(.headline)
            Chart(Array(points), id: \.week) { p in
                AreaMark(x: .value("Week", p.week, unit: .weekOfYear), y: .value("Check-ins", p.count))
                    .foregroundStyle(LinearGradient(colors: [Brand.teal.opacity(0.5), Brand.teal.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Week", p.week, unit: .weekOfYear), y: .value("Check-ins", p.count))
                    .foregroundStyle(Brand.teal).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(x: .value("Week", p.week, unit: .weekOfYear), y: .value("Check-ins", p.count)).foregroundStyle(Brand.teal)
            }
            .frame(height: 160)
        }
        .padding(16).glass(22)
    }

    // MARK: Tasks

    @ViewBuilder private var tasks: some View {
        let all = model.tasks
        let open = all.filter { !model.isDone($0) }
        let overdue = open.filter { !$0.effectiveDue.isEmpty && $0.effectiveDue < Day.iso() }
        let fortnight = Date().addingTimeInterval(-14 * 86400).timeIntervalSince1970 * 1000
        let recentlyDone = all.filter { model.isDone($0) && $0.updatedAt > fortnight }
        HStack(spacing: 10) {
            StatTile(value: "\(open.count)", label: "Open", systemImage: "circle.dashed", color: Brand.blue)
            StatTile(value: "\(overdue.count)", label: "Overdue", systemImage: "exclamationmark.triangle.fill", color: overdue.isEmpty ? .secondary : .red)
            StatTile(value: "\(recentlyDone.count)", label: "Done, 2 weeks", systemImage: "checkmark.circle.fill", color: .green)
        }
        VStack(alignment: .leading, spacing: 10) {
            Text("By board").font(.headline)
            // Plain rows with stacked segments (not Swift Charts, whose axis labels landed on the bars on a phone)
            let colors: [String: Color] = ["todo": Brand.blue, "doing": Brand.amber, "done": .green, "grants": Brand.violet]
            let rowsByBoard = model.boards.map { b in
                (b, model.columns(for: b.id).map { c in (c, all.filter { $0.subteamId == b.id && $0.columnId == c.id }.count) }.filter { $0.1 > 0 })
            }
            let most = max(rowsByBoard.map { $0.1.reduce(0) { $0 + $1.1 } }.max() ?? 1, 1)
            VStack(spacing: 8) {
                ForEach(rowsByBoard, id: \.0.id) { b, parts in
                    let total = parts.reduce(0) { $0 + $1.1 }
                    HStack(spacing: 10) {
                        Text(b.name).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7).frame(width: 96, alignment: .leading)
                        GeometryReader { g in
                            HStack(spacing: 2) {
                                ForEach(parts, id: \.0.id) { c, n in
                                    Capsule().fill(colors[c.id] ?? Brand.teal)
                                        .frame(width: max(4, (g.size.width - CGFloat(parts.count) * 2) * CGFloat(n) / CGFloat(most)))
                                }
                            }
                            .frame(height: 12).frame(maxHeight: .infinity)
                        }
                        .frame(height: 16)
                        Text("\(total)").font(.caption.weight(.semibold)).monospacedDigit().frame(width: 28, alignment: .trailing)
                    }
                }
                HStack(spacing: 14) {
                    ForEach([("To Do", Brand.blue), ("In Progress", Brand.amber), ("Done", Color.green)]
                            + (rowsByBoard.contains { $0.1.contains { $0.0.id == "grants" } } ? [("Grants", Brand.violet)] : []), id: \.0) { name, color in
                        HStack(spacing: 5) { Circle().fill(color).frame(width: 8, height: 8); Text(name) }
                    }
                }
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
        .padding(16).glass(22)
        let owners = Dictionary(grouping: open.flatMap { t in t.assigneeUids.map { ($0, t) } }, by: \.0).mapValues(\.count)
            .sorted { $0.value > $1.value }.prefix(10)
        if !owners.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Most on their plate").font(.headline).padding(.bottom, 8)
                ForEach(Array(owners), id: \.key) { uid, n in
                    HStack(spacing: 12) {
                        PersonAvatar(id: uid, size: 28)
                        Text(model.person(uid)?.name ?? "Someone").font(.subheadline)
                        Spacer()
                        Text("\(n) open").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(16).glass(22)
        }
    }
}

/// Every message sent to the helper (Gemini), newest first. Only reviewers (assistantAccess/reviewers) can read it.
struct HelperChatsView: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [HelperLog]?
    @State private var failed = ""
    @State private var query = ""
    @State private var limit = 200

    var body: some View {
        List {
            if let rows {
                let shown = query.isEmpty ? rows : rows.filter { [$0.name, $0.said, $0.reply].contains { $0.localizedCaseInsensitiveContains(query) } }
                let days = Dictionary(grouping: shown, by: \.day)
                if shown.isEmpty { Text(rows.isEmpty ? "No chats yet." : "Nothing matches.").foregroundStyle(.secondary) }
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    Section(Day.date(day)?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) ?? day) {
                        ForEach(days[day]!) { e in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(e.name.isEmpty ? "Someone" : e.name).font(.subheadline.weight(.semibold))
                                    Text(Date(timeIntervalSince1970: e.at / 1000), format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                                    if e.status != 0 && e.status != 200 { Pill(text: "Error \(e.status)", tint: .red) }
                                }
                                if !e.said.isEmpty { Text(e.said) }
                                if !e.reply.isEmpty { Text(e.reply).font(.subheadline).foregroundStyle(.secondary) }
                                if !e.calls.isEmpty { Text("Suggested: \(e.calls.joined(separator: ", "))").font(.caption).foregroundStyle(Brand.violet) }
                                if !e.error.isEmpty { Text(e.error).font(.caption).foregroundStyle(.red) }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowBackground(Color.row)
                }
                if rows.count >= limit { Button("Show older") { limit += 200; Task { await load() } } }
            } else if !failed.isEmpty {
                Text(failed).foregroundStyle(.secondary)
            } else {
                SkeletonRows(count: 5).listRowBackground(Color.clear)
            }
        }
        .searchable(text: $query, prompt: "Search by name or words")
        .scrollContentBackground(.hidden)
        .appBackground(Brand.violet)
        .navigationTitle("Helper chats")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { rows = try await model.helperLogs(limit: limit) } catch { failed = "Couldn't load the chats: \(AppModel.friendly(error))" }
    }
}

/// What the Slack bot keeps from #meeting-signups, as text to save or share. They name students: leads only.
struct SignupRecordsView: View {
    @Environment(AppModel.self) private var model
    @State private var busy = ""
    @State private var file: URL?

    var body: some View {
        List {
            Section {
                row("log", "Slack log", "Every message in #meeting-signups and every signup the bot made", "text.bubble.fill", Brand.blue)
                row("export", "Weekly export", "All signups and attendance, as of the latest week", "tablecells.fill", Brand.teal)
            } footer: {
                Text("Plain text files. They name students, so keep them off shared drives and out of Slack.")
            }
            .listRowBackground(Color.row)
            if let file {
                Section {
                    ShareLink(item: file) { Label("Save or share \(file.lastPathComponent)", systemImage: "square.and.arrow.up") }
                }
                .listRowBackground(Color.row)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Signup records")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ id: String, _ title: String, _ hint: String, _ icon: String, _ color: Color) -> some View {
        Button { get(id) } label: {
            HStack(spacing: 12) {
                IconTile(systemImage: icon, color: color, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if busy == id { ProgressView() }
            }
        }
        .disabled(!busy.isEmpty)
    }

    private func get(_ which: String) {
        busy = which
        Task {
            defer { busy = "" }
            do {
                let name: String, text: String
                if which == "log" {
                    guard let t = try await model.signupLogText() else { model.toast = "Nothing in the log yet."; return }
                    (name, text) = ("sor-signup-log-\(Day.iso()).txt", t)
                } else {
                    guard let x = try await model.latestExportText() else { model.toast = "No weekly export yet."; return }
                    (name, text) = ("sor-signups-attendance-\(x.day).txt", x.text)
                }
                let url = FileManager.default.temporaryDirectory.appending(path: name)
                try text.write(to: url, atomically: true, encoding: .utf8)
                file = url
            } catch {
                model.toast = AppModel.friendly(error).contains("permission") ? "Only leads can download these." : AppModel.friendly(error)
            }
        }
    }
}

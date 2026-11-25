import SwiftUI

/// Timeline: Pinboard (the big goals as sticky notes, in date order, with competitions where they fall)
/// and Schedule (every dated task by week, with what's running late).
struct SeasonTimelineView: View {
    enum Mode: String, CaseIterable { case pinboard = "Pinboard", schedule = "Schedule" }
    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .pinboard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("View", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented)
                Text(mode == .pinboard ? "The team's goals and each subteam's priorities, in date order." : "When everything is due, and what's running late.")
                    .font(.footnote).foregroundStyle(.secondary)
                if mode == .pinboard { Pinboard() } else { Schedule() }
            }
            .padding(.horizontal, 16).padding(.bottom, 28)
        }
        .appBackground(Brand.violet)
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: TaskItem.self) { TaskDetailView(taskId: $0.id) }
    }
}

private let noteTints: [Color] = [Brand.amber, Brand.blue, Brand.violet, .green, .pink]

private struct Pinboard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let goals = model.pinboardGoals
        let comps = model.upcoming.filter { $0.isCompetition && !$0.isNotCompeting }
        if !model.loaded.contains("tasks") { SkeletonRows(count: 3) }
        else if goals.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "pin.fill").font(.largeTitle).foregroundStyle(Brand.amber)
                Text("No goals pinned up yet").font(.headline)
                Text("Team goals and subteam priorities show up here as sticky notes. On the website, open a card and turn on “This is an overall goal”.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(28).glass(22)
        } else {
            VStack(spacing: 18) {
                ForEach(Array(entries(goals, comps).enumerated()), id: \.offset) { i, e in
                    switch e {
                    case .goal(let g, let n): note(g, n, left: i % 2 == 0)
                    case .comp(let c): compBand(c)
                    }
                }
            }
        }
    }

    enum Entry { case goal(AppModel.Goal, Int), comp(CalEvent) }

    /// Competitions sit in the line where they fall.
    private func entries(_ goals: [AppModel.Goal], _ comps: [CalEvent]) -> [Entry] {
        var out: [Entry] = []
        var ci = 0
        for (n, g) in goals.enumerated() {
            while ci < comps.count, !g.task.dueDate.isEmpty, comps[ci].dayKey <= g.task.dueDate { out.append(.comp(comps[ci])); ci += 1 }
            out.append(.goal(g, n))
        }
        if ci < comps.count, goals.last?.task.dueDate.isEmpty == false { out.append(.comp(comps[ci])) }
        return out
    }

    private func note(_ g: AppModel.Goal, _ n: Int, left: Bool) -> some View {
        let team = g.task.subteamId == "goals"
        let tint = team ? noteTints[n % noteTints.count] : model.subteam(g.task.subteamId)?.color ?? Brand.blue
        let done = model.isDone(g.task)
        return VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: g.task) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(format: "%02d", n + 1)).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(tint.opacity(0.9))
                        Spacer()
                        Image(systemName: "pin.fill").foregroundStyle(.red).rotationEffect(.degrees(30)).font(.title3)
                    }
                    Text(g.task.title).font(.title3.weight(.bold)).multilineTextAlignment(.leading).strikethrough(done)
                    HStack(spacing: 6) {
                        Text(team ? "Team goal" : "\(model.subteam(g.task.subteamId)?.name ?? "Subteam") priority")
                        Text("·")
                        if g.task.dueDate.isEmpty { Text("no date yet") }
                        else { Text(done ? "done" : "due \(Day.pretty(g.task.dueDate))\(g.late ? " · late" : "")").foregroundStyle(g.late ? .red : .secondary) }
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    if !g.parts.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView(value: Double(g.done), total: Double(g.parts.count)).tint(tint)
                            Text("\(g.done) of \(g.parts.count)").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [tint.opacity(0.34), tint.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .background(Color.row, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                .rotationEffect(.degrees(left ? -1.2 : 1.2))
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(.primary)
            if !g.parts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(g.parts.prefix(6)) { p in
                        NavigationLink(value: p) { partRow(p) }.buttonStyle(.plain)
                    }
                    if g.parts.count > 6 { Text("+\(g.parts.count - 6) more").font(.caption).foregroundStyle(.secondary).padding(.leading, 30).padding(.top, 4) }
                }
                .padding(.leading, 14)
            }
        }
    }

    private func partRow(_ p: TaskItem) -> some View {
        let done = model.isDone(p)
        let late = model.isLate(p)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : late ? "exclamationmark.circle.fill" : p.isGoal ? "target" : "circle")
                .foregroundStyle(done ? .green : late ? .red : model.subteam(p.subteamId)?.color ?? .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).font(.subheadline.weight(.medium)).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
                let who = p.assigneeUids.compactMap { model.person($0)?.firstName }
                Text([model.subteam(p.subteamId)?.name ?? "", who.prefix(2).joined(separator: ", "), p.dueDate.isEmpty ? "" : (done ? "done" : "due \(Day.pretty(p.dueDate))")]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(late ? .red : .secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1.5).offset(x: -8) }
    }

    private func compBand(_ c: CalEvent) -> some View {
        let days = max(0, Day.until(c.dayKey) ?? 0)
        return HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text(c.title).font(.subheadline.weight(.bold))
                Text("\(c.startDate.formatted(.dateTime.weekday(.abbreviated).month().day())) · in \(days) days").font(.caption)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(Brand.wash(Brand.red), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct Schedule: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let dated = model.tasks.filter { !$0.effectiveDue.isEmpty }.sorted { ($0.effectiveDue, $0.position) < ($1.effectiveDue, $1.position) }
        let weeks = Dictionary(grouping: dated) { weekStart($0.effectiveDue) }
        let comps = model.events.filter { $0.isCompetition && !$0.isNotCompeting }
        let late = dated.filter { model.isLate($0) }
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                StatTile(value: "\(dated.filter { !model.isDone($0) }.count)", label: "Dated, open", systemImage: "calendar", color: Brand.blue)
                StatTile(value: "\(late.count)", label: "Running late", systemImage: "exclamationmark.triangle.fill", color: late.isEmpty ? .secondary : .red)
            }
            ForEach(weeks.keys.sorted(), id: \.self) { w in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(weekLabel(w)).font(.headline)
                        Spacer()
                        ForEach(comps.filter { weekStart($0.dayKey) == w }) { c in
                            Label(c.title, systemImage: "trophy.fill").font(.caption.weight(.bold)).foregroundStyle(Brand.red).lineLimit(1)
                        }
                    }
                    ForEach(weeks[w]!) { t in
                        NavigationLink(value: t) { scheduleRow(t) }.buttonStyle(.plain)
                    }
                }
            }
            if dated.isEmpty && model.loaded.contains("tasks") { Text("No tasks have dates yet.").foregroundStyle(.secondary) }
        }
    }

    private func scheduleRow(_ t: TaskItem) -> some View {
        let done = model.isDone(t), late = model.isLate(t)
        let c = model.subteam(t.subteamId)?.color ?? Brand.blue
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(Day.date(t.effectiveDue)?.formatted(.dateTime.weekday(.abbreviated)) ?? "").font(.caption2.weight(.bold)).foregroundStyle(c)
                Text(Day.date(t.effectiveDue)?.formatted(.dateTime.day()) ?? "").font(.headline.weight(.bold))
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.title).font(.subheadline.weight(.semibold)).strikethrough(done || late, color: late ? .red : .secondary)
                    .foregroundStyle(done ? .secondary : .primary).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    SubteamDot(color: c, size: 7)
                    Text(model.subteam(t.subteamId)?.name ?? "")
                    if !t.newDueDate.isEmpty { Text("· moved from \(Day.pretty(t.dueDate))") }
                    if late { Text(t.effectiveDue < Day.iso() ? "· overdue" : "· waiting on a late task").foregroundStyle(.red) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
        .padding(12)
        .glass(16, tint: late ? .red : nil)
    }

    private func weekStart(_ iso: String) -> String {
        guard let d = Day.date(iso) else { return iso }
        let cal = Calendar.current
        return Day.iso(cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? d)
    }

    private func weekLabel(_ iso: String) -> String {
        guard let d = Day.date(iso) else { return iso }
        let thisWeek = weekStart(Day.iso())
        if iso == thisWeek { return "This week" }
        if iso < thisWeek { return "Week of \(d.formatted(.dateTime.month(.abbreviated).day())) · past" }
        return "Week of \(d.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

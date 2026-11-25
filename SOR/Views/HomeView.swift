import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var tab: AppTab
    @State private var openMeeting: CalEvent?
    @State private var sendingHere = false
    @State private var checkingIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    stats
                    if let m = model.meetingNow { hereCard(m) }
                    else if let sh = model.openShifts.first, let e = sh.event { hereCard(e) }
                    if let next = nextMeeting { nextUp(next) }
                    if let comp = model.nextCompetition { competitionCard(comp) }
                    comingUp
                    myWork
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .appBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TaskItem.self) { TaskDetailView(taskId: $0.id) }
            .sheet(item: $openMeeting) { MeetingDetailView(event: $0) }
            .sheet(isPresented: $checkingIn) { CheckInSheet() }
            .refreshable { model.refreshCalendar(force: true) }
        }
    }

    // MARK: Header

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
                Text("\(greeting), \(model.profile?.firstName ?? "")").font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer()
            Button { tab = .you } label: {
                Avatar(name: model.profile?.name ?? "", photoURL: model.authPhoto, size: 44)
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            .accessibilityLabel("You")
        }
        .padding(.top, 12)
    }

    // MARK: Stats

    private var stats: some View {
        let mine = model.myOpenTasks
        let soon = mine.filter { (Day.until($0.dueDate) ?? 99) <= 3 }.count
        return HStack(spacing: 10) {
            Button { tab = .tasks } label: { StatTile(value: "\(mine.count)", label: "My tasks", systemImage: "checklist", color: Brand.blue) }
            StatTile(value: "\(soon)", label: "Due soon", systemImage: "clock.badge.exclamationmark", color: soon > 0 ? Brand.amber : .secondary)
            StatTile(value: "\(model.myOpenActionItems.count)", label: "Action items", systemImage: "checkmark.circle", color: Brand.teal)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: mine.count)
    }

    // MARK: At a meeting: check in, and "I'm here"

    private func hereCard(_ m: CalEvent) -> some View {
        let canCheckIn = model.openShifts.contains { $0.id == m.id }
        let marked = model.myMarks.first { $0.meetingId == m.id }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(.green).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.green.opacity(0.4), lineWidth: 6).scaleEffect(1.6))
                Text("HAPPENING NOW").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.85)).tracking(0.8)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(m.title).font(.title2.weight(.bold)).foregroundStyle(.white)
                Text("\(m.whenLabel) · \(m.shortPlace)").font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
            if let marked, let st = MarkStatus(rawValue: marked.status) {
                Label("Checked in · \(st.label)", systemImage: "checkmark.seal.fill").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8).background(.white.opacity(0.2), in: Capsule()).foregroundStyle(.white)
            } else if canCheckIn {
                Button { checkingIn = true } label: {
                    Label("Scan to check in", systemImage: "qrcode.viewfinder").font(.headline)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .foregroundStyle(kindColor(m))
                }
                .buttonStyle(PressableStyle())
            }
            if model.imHere {
                Label("The team knows you're here", systemImage: "hand.wave.fill").font(.subheadline).foregroundStyle(.white.opacity(0.85))
            } else {
                Button {
                    sendingHere = true
                    Task { await model.announceArrival(); sendingHere = false }
                } label: {
                    HStack { if sendingHere { ProgressView().tint(.white) } else { Image(systemName: "hand.wave.fill") }; Text("I'm here, open the door") }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 44)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableStyle())
                .disabled(sendingHere)
            }
        }
        .padding(18)
        .background(Brand.wash(kindColor(m)), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: kindColor(m).opacity(0.35), radius: 18, y: 10)
    }

    // MARK: Next up

    private var nextMeeting: CalEvent? {
        let now = Date().timeIntervalSince1970 * 1000
        return model.events.first { !$0.allDay && $0.start > now && !model.isCancelled($0) && $0.id != model.meetingNow?.id }
    }

    private func nextUp(_ e: CalEvent) -> some View {
        let c = kindColor(e)
        return Button { openMeeting = e } label: {
            HStack(spacing: 16) {
                VStack(spacing: 0) {
                    Text(e.startDate.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.caption2.weight(.bold)).foregroundStyle(c)
                    Text(e.startDate.formatted(.dateTime.day())).font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(e.startDate.formatted(.dateTime.month(.abbreviated))).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
                .frame(width: 62, height: 74)
                .background(c.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text("NEXT UP · \(relative(e))").font(.caption.weight(.bold)).foregroundStyle(c).tracking(0.5)
                    Text(e.title).font(.headline).multilineTextAlignment(.leading).lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: e.place.isEmpty ? "video.fill" : "mappin.circle.fill").foregroundStyle(.secondary)
                        Text(e.place.isEmpty ? (e.service.isEmpty ? e.whenLabel : "\(e.whenLabel) · \(e.service)") : "\(e.whenLabel) · \(e.shortPlace)")
                            .lineLimit(1)
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.amGoing(e.id) {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green).symbolRenderingMode(.hierarchical)
                }
            }
            .padding(14)
            .glass(22, tint: c)
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.primary)
    }

    private func relative(_ e: CalEvent) -> String {
        let n = Day.until(e.dayKey) ?? 0
        if n == 0 {
            let mins = Int((e.start - Date().timeIntervalSince1970 * 1000) / 60_000)
            return mins < 60 ? "IN \(max(1, mins)) MIN" : "TODAY"
        }
        return n == 1 ? "TOMORROW" : "IN \(n) DAYS"
    }

    // MARK: Competition

    private func competitionCard(_ c: CalEvent) -> some View {
        let days = max(0, Day.until(c.dayKey) ?? 0)
        return Button { openMeeting = c } label: {
            HStack(spacing: 16) {
                ZStack {
                    Ring(progress: 1 - Double(min(days, 120)) / 120, color: Brand.red, width: 7)
                    VStack(spacing: -2) {
                        Text("\(days)").font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(days == 1 ? "day" : "days").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Next competition", systemImage: "trophy.fill").font(.caption.weight(.bold)).foregroundStyle(Brand.red).textCase(.uppercase)
                    Text(c.title).font(.headline).multilineTextAlignment(.leading)
                    Text(c.startDate.formatted(.dateTime.weekday(.wide).month().day())).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .glass(22, tint: Brand.red)
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.primary)
    }

    // MARK: Coming up

    private var comingUp: some View {
        let list = model.upcoming.filter { !$0.allDay && $0.id != nextMeeting?.id && $0.id != model.meetingNow?.id }.prefix(8)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Coming up")
                Button("See all") { tab = .meetings }.font(.subheadline.weight(.medium))
            }
            if !model.loaded.contains("calendar") {
                SkeletonRows(count: 1)
            } else if list.isEmpty {
                Text("Nothing else on the calendar.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(list)) { e in
                            Button { openMeeting = e } label: { miniMeeting(e) }.buttonStyle(PressableStyle()).foregroundStyle(.primary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func miniMeeting(_ e: CalEvent) -> some View {
        let c = kindColor(e)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(e.startDate.formatted(.dateTime.weekday(.abbreviated).day())).font(.caption.weight(.bold)).foregroundStyle(c)
                Spacer()
                if model.amGoing(e.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                if model.isCancelled(e) { Text("Cancelled").font(.caption2.weight(.bold)).foregroundStyle(.red) }
            }
            Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading).strikethrough(model.isCancelled(e))
            Spacer(minLength: 0)
            Text(e.whenLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(width: 160, height: 116, alignment: .topLeading)
        .glass(18, tint: c)
    }

    // MARK: My work

    private var myWork: some View {
        let mine = model.myOpenTasks
        let items = model.myOpenActionItems
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "My work")
            if !model.loaded.contains("tasks") {
                SkeletonRows(count: 3)
            } else if mine.isEmpty {
                HStack(spacing: 12) {
                    IconTile(systemImage: "sparkles", color: Brand.teal, size: 36)
                    Text("Nothing assigned to you right now.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .glass(18)
            } else {
                ForEach(mine) { t in
                    NavigationLink(value: t) { TaskRow(task: t, showBoard: true) }.buttonStyle(.plain)
                }
            }
            if !items.isEmpty {
                SectionTitle(text: "My action items")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { a in ActionItemRow(item: a) }
                }
                .padding(14)
                .glass(18, tint: Brand.teal)
            }
        }
    }
}

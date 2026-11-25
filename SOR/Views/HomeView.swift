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
                VStack(alignment: .leading, spacing: 16) {
                    if let m = model.meetingNow { hereCard(m) }
                    else if let sh = model.openShifts.first, let e = sh.event { hereCard(e) }
                    if let comp = model.nextCompetition { competitionCard(comp) }
                    nextMeetings
                    myWork
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.page)
            .navigationTitle(greeting)
            .navigationDestination(for: TaskItem.self) { TaskDetailView(taskId: $0.id) }
            .sheet(item: $openMeeting) { MeetingDetailView(event: $0) }
            .sheet(isPresented: $checkingIn) { CheckInSheet() }
            .refreshable { model.refreshCalendar(force: true) }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return "\(part), \(model.profile?.firstName ?? "")"
    }

    // MARK: At a meeting: check in, and "I'm here"

    private func hereCard(_ m: CalEvent) -> some View {
        let canCheckIn = model.openShifts.contains { $0.id == m.id }
        let marked = model.myMarks.first { $0.meetingId == m.id }
        return Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(m.title).font(.headline)
                Text("\(m.whenLabel) · \(m.shortPlace)").font(.subheadline).foregroundStyle(.secondary)
            }
            if let marked, let st = MarkStatus(rawValue: marked.status) {
                Label("Checked in: \(st.label)", systemImage: "checkmark.seal.fill").foregroundStyle(st.tint).font(.subheadline.weight(.medium))
            } else if canCheckIn {
                Button { checkingIn = true } label: {
                    Label("Scan to check in", systemImage: "qrcode.viewfinder").font(.headline).frame(maxWidth: .infinity).frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
            }
            if model.imHere {
                Label("The team knows you're here", systemImage: "hand.wave.fill").foregroundStyle(.secondary).font(.subheadline)
            } else {
                Button {
                    sendingHere = true
                    Task { await model.announceArrival(); sendingHere = false }
                } label: {
                    HStack { if sendingHere { ProgressView() } else { Image(systemName: "hand.wave.fill") }; Text("I'm here, open the door") }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 40)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .disabled(sendingHere)
            }
        }
    }

    // MARK: Competition

    private func competitionCard(_ c: CalEvent) -> some View {
        let days = Day.until(c.dayKey) ?? 0
        return Card {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text("\(max(0, days))").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(days == 1 ? "day" : "days").font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next competition").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    Text(c.title).font(.headline)
                    Text(c.startDate.formatted(.dateTime.weekday(.wide).month().day())).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .onTapGesture { openMeeting = c }
    }

    // MARK: Meetings

    private var nextMeetings: some View {
        let list = model.upcoming.filter { !$0.allDay }.prefix(3)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Coming up")
                Button("All") { tab = .meetings }.font(.subheadline)
            }
            if !model.loaded.contains("calendar") {
                SkeletonRows(count: 2)
            } else if list.isEmpty {
                Text("Nothing on the calendar.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(list)) { e in
                    Button { openMeeting = e } label: { MeetingRow(event: e) }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: My work

    private var myWork: some View {
        let mine = model.myOpenTasks
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "My work")
            if !model.loaded.contains("tasks") {
                SkeletonRows(count: 3)
            } else if mine.isEmpty {
                Card {
                    Label("Nothing assigned to you right now.", systemImage: "checkmark.seal").foregroundStyle(.secondary)
                }
            } else {
                ForEach(mine) { t in
                    NavigationLink(value: t) { TaskRow(task: t, showBoard: true) }.buttonStyle(.plain)
                }
            }
            let items = model.myOpenActionItems
            if !items.isEmpty {
                SectionTitle(text: "My action items")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { a in ActionItemRow(item: a) }
                }
                .padding(14)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var tab: AppTab
    @State private var openMeeting: CalEvent?
    @State private var sendingHere = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let m = model.meetingNow { hereCard(m) }
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
            .refreshable { model.refreshCalendar(force: true) }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return "\(part), \(model.profile?.firstName ?? "")"
    }

    // MARK: I'm here

    private func hereCard(_ m: CalEvent) -> some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.title).font(.headline)
                    Text("\(m.whenLabel) · \(m.shortPlace)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if model.imHere {
                Label("You're checked in for today", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline.weight(.medium))
            } else {
                Button {
                    sendingHere = true
                    Task { await model.announceArrival(); sendingHere = false }
                } label: {
                    HStack { if sendingHere { ProgressView() } else { Image(systemName: "hand.wave.fill") }; Text("I'm here") }
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .disabled(sendingHere)
                Text("Lets the team know, and rings the Monitor so someone opens the door.").font(.footnote).foregroundStyle(.secondary)
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
        }
    }
}

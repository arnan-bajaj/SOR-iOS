import WidgetKit
import SwiftUI

struct Entry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snap: context.isPreview ? .sample : WidgetSnapshot.load() ?? .sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snap = WidgetSnapshot.load()
        // Redraw when the next meeting ends, so it moves on to the one after, and at least every hour.
        let now = Date()
        let next = snap?.meetings.map(\.end).filter { $0 > now }.min() ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [Entry(date: now, snap: snap)], policy: .after(min(next, now.addingTimeInterval(3600)))))
    }
}

struct NextMeetingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        let now = entry.date
        let meetings = (entry.snap?.meetings ?? []).filter { $0.end > now }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image("Logo").resizable().scaledToFill().frame(width: 18, height: 18).clipShape(Circle())
                Text(family == .systemSmall ? "Next up" : "Coming up").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let s = entry.snap, s.openTasks > 0, family != .systemSmall {
                    Label("\(s.openTasks)", systemImage: "checklist").font(.caption.weight(.semibold)).foregroundStyle(s.dueSoon > 0 ? .orange : .secondary)
                }
            }
            if entry.snap == nil {
                Text("Open the app to sign in.").font(.subheadline).foregroundStyle(.secondary)
            } else if meetings.isEmpty {
                Text("Nothing on the calendar.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(meetings.prefix(family == .systemSmall ? 1 : 2), id: \.self) { m in
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(when(m, now)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if family != .systemSmall, !m.place.isEmpty { Text(m.place).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
            if let s = entry.snap, let d = s.competitionDate, !s.competition.isEmpty {
                let days = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: d)).day ?? 0)
                Text("\(days) days to \(s.competition)").font(.caption2.weight(.medium)).foregroundStyle(.red).lineLimit(1)
            }
        }
        .containerBackground(for: .widget) { Color(red: 0x1C / 255, green: 0x21 / 255, blue: 0x25 / 255) }
        .environment(\.colorScheme, .dark)
    }

    private func when(_ m: WidgetSnapshot.Meeting, _ now: Date) -> String {
        if m.start <= now { return "Now · until \(m.end.formatted(date: .omitted, time: .shortened))" }
        let day = Calendar.current.isDateInToday(m.start) ? "Today" : Calendar.current.isDateInTomorrow(m.start) ? "Tomorrow" : m.start.formatted(.dateTime.weekday(.abbreviated))
        return m.allDay ? "\(day) · All day" : "\(day) · \(m.start.formatted(date: .omitted, time: .shortened))"
    }
}

@main
struct SORWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextMeeting", provider: Provider()) { NextMeetingView(entry: $0) }
            .configurationDisplayName("Next meeting")
            .description("The team's next meetings and the countdown to the next competition.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

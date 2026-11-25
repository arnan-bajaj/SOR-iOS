import SwiftUI

/// The Board Room: confidential. The Board writes; lead mentors read; nobody else can load any of it.
/// Three parts, like the website: the channel, the confidential action items, and the Board's agendas.
struct BoardRoomView: View {
    enum Part: String, CaseIterable { case channel = "Channel", items = "Action items", agendas = "Agendas" }
    @Environment(AppModel.self) private var model
    @State private var part: Part = .channel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Part", selection: $part) { ForEach(Part.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented)
                Label("Only the Board and lead mentors can see this.", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
            switch part {
            case .channel: BoardChannelView()
            case .items: ActionItemsView(boardRoom: true, embedded: true)
            case .agendas: AgendaDocsList(track: .board)
            }
        }
        .appBackground(Brand.red)
        .navigationTitle("Board Room")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.wantBoardRoom() }
    }
}

private struct BoardChannelView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var choosingSeason = false
    @State private var reporting: ReportTarget?
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        seasonCard
                        if !model.loaded.contains("boardChannel") && !model.demo { SkeletonRows(count: 4) }
                        else if model.boardChannel.isEmpty { Text("No messages yet.").foregroundStyle(.secondary).padding(.top, 20) }
                        ForEach(model.boardChannel.filter { !model.isBlocked($0.authorId) }) { m in message(m).id(m.id) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
                .onChange(of: model.boardChannel.count) { _, _ in withAnimation { proxy.scrollTo(model.boardChannel.last?.id, anchor: .bottom) } }
                .onAppear { proxy.scrollTo(model.boardChannel.last?.id, anchor: .bottom) }
            }
            .sheet(item: $reporting) { ReportSheet(target: $0) }
            if model.isBoardMember {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message the Board", text: $text, axis: .vertical).lineLimit(1...5).focused($typing)
                        .padding(.horizontal, 14).padding(.vertical, 10).glass(20)
                    Button {
                        let t = text; text = ""
                        Task { await model.postToBoard(t) }
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).symbolRenderingMode(.hierarchical) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
        .confirmationDialog("Move the whole team to…", isPresented: $choosingSeason, titleVisibility: .visible) {
            ForEach(model.seasons.filter { $0.id != model.currentSeason.id }) { s in
                Button(s.name) { Task { await model.switchSeason(to: s) } }
            }
        } message: { Text("Everyone switches right away. Days from today on belong to the new season. It can be undone.") }
    }

    private var seasonCard: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: "calendar.badge.clock", color: Brand.violet, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("The team is on").font(.caption).foregroundStyle(.secondary)
                Text(model.currentSeason.name).font(.headline)
            }
            Spacer()
            if model.seasons.count > 1 { Button("Switch") { choosingSeason = true }.buttonStyle(.bordered) }
        }
        .padding(12).glass(18, tint: Brand.violet)
    }

    @ViewBuilder private func message(_ m: ChannelMessage) -> some View {
        if m.kind == "season" {
            Label(m.text, systemImage: "calendar.badge.clock").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        } else {
            let mine = m.authorId == model.uid
            HStack(alignment: .top, spacing: 10) {
                if !mine { PersonAvatar(id: m.authorId, size: 30) } else { Spacer(minLength: 40) }
                VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if !mine { Text(model.person(m.authorId)?.name ?? m.authorName).font(.caption.weight(.semibold)) }
                        Text(Date(timeIntervalSince1970: m.createdAt / 1000), format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(m.text).textSelection(.enabled)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(mine ? AnyShapeStyle(Brand.wash(Brand.blue)) : AnyShapeStyle(Color.row), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(mine ? .white : .primary)
                }
                if mine { EmptyView() } else { Spacer(minLength: 40) }
            }
            .contextMenu {
                ReportMenuItems(target: ReportTarget(kind: "message", path: "boardChannel/\(m.id)", authorUid: m.authorId, text: m.text)) { reporting = $0 }
            }
        }
    }
}

/// The agendas written on the website for one kind of meeting, plus the Google Doc ones /agenda made in Slack.
struct AgendaDocsList: View {
    @Environment(AppModel.self) private var model
    let track: Track

    var body: some View {
        let d = model.docs(for: track)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if d.agendas.isEmpty && d.google.isEmpty {
                    Text("No agendas yet. Start one on the website, or with /agenda in Slack.").foregroundStyle(.secondary).padding(.top, 20)
                }
                ForEach(d.google) { g in
                    if let url = URL(string: g.url) {
                        Link(destination: url) {
                            HStack(spacing: 12) {
                                IconTile(systemImage: "doc.richtext.fill", color: Brand.blue, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.title.isEmpty ? "Agenda" : g.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                                    Text("Google Doc · \(Day.pretty(g.date))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                            }
                            .padding(12).glass(16)
                        }
                        .foregroundStyle(.primary)
                    }
                }
                ForEach(d.agendas) { a in
                    NavigationLink(value: a) {
                        HStack(spacing: 12) {
                            IconTile(systemImage: "list.bullet.rectangle.fill", color: Brand.violet, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(track.label) agenda").font(.subheadline.weight(.semibold))
                                Text("\(Day.pretty(a.date))\(a.startTime.isEmpty ? "" : " · \(a.startTime)") · \(a.items.count) topics · \(a.totalMinutes) min")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(12).glass(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .navigationDestination(for: AgendaDoc.self) { AgendaDocView(doc: $0) }
        .onAppear { model.wantAgendaDocs() }
    }
}

struct AgendaDocView: View {
    let doc: AgendaDoc
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Track(rawValue: doc.track)?.label ?? "Meeting") agenda").font(.title2.weight(.bold))
                    Text("\(Day.date(doc.date)?.formatted(.dateTime.weekday(.wide).month().day()) ?? doc.date)\(doc.startTime.isEmpty ? "" : " · \(doc.startTime)")").foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.row)
            if !doc.items.isEmpty {
                Section("Topics · \(doc.totalMinutes) min") {
                    ForEach(Array(doc.items.enumerated()), id: \.offset) { _, it in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(it.topic).font(.headline)
                                Spacer()
                                if it.minutes > 0 { Text("\(it.minutes) min").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                                if !it.urgency.isEmpty { Pill(text: it.urgency.capitalized, tint: it.urgency == "high" ? .red : it.urgency == "medium" ? .orange : .secondary) }
                            }
                            if !it.points.isEmpty { Text(it.points).font(.subheadline).foregroundStyle(.secondary) }
                            if !it.who.isEmpty { Text("Who: \(it.who)").font(.caption).foregroundStyle(.secondary) }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowBackground(Color.row)
            }
            notes("Purpose", doc.purpose)
            notes("Key takeaways", doc.takeaways)
            notes("Topics discussed", doc.topics)
            notes("Next steps", doc.nextSteps)
            if !doc.attended.isEmpty {
                Section("Attended") { Text(doc.attended.joined(separator: ", ")) }.listRowBackground(Color.row)
            }
            if let url = URL(string: doc.recording), !doc.recording.isEmpty {
                Section { Link(destination: url) { Label("Recording", systemImage: "play.rectangle.fill") } }.listRowBackground(Color.row)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground(Brand.violet)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func notes(_ title: String, _ text: String) -> some View {
        if !text.isEmpty { Section(title) { Text(text).textSelection(.enabled) }.listRowBackground(Color.row) }
    }
}

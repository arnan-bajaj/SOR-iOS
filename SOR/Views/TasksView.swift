import SwiftUI

/// Tasks: every subteam board, then one board's columns.
struct TasksView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if !model.loaded.contains("subteams") {
                    SkeletonRows(count: 6).listRowBackground(Color.clear)
                }
                Section {
                    NavigationLink(value: "mine") {
                        BoardRow(name: "My Work", color: .accentColor, systemImage: "person.fill", count: model.myOpenTasks.count)
                    }
                }
                .listRowBackground(Color.row)
                Section {
                    NavigationLink(value: TasksPage.actions) {
                        BoardRow(name: "Action Items", color: .cyan, systemImage: "checklist", count: model.myOpenActionItems.count)
                    }
                    NavigationLink(value: TasksPage.timeline) {
                        BoardRow(name: "Timeline", color: .indigo, systemImage: "calendar.day.timeline.left", count: 0)
                    }
                }
                .listRowBackground(Color.row)
                Section("Boards") {
                    ForEach(model.boards) { s in
                        NavigationLink(value: s.id) {
                            BoardRow(name: s.name, color: s.color, systemImage: boardSymbol(s.id), count: model.tasks.filter { $0.subteamId == s.id && !model.isDone($0) }.count)
                        }
                    }
                }
                .listRowBackground(Color.row)
                Section {
                    NavigationLink(value: TasksPage.archive) {
                        BoardRow(name: "Archive", color: .gray, systemImage: "archivebox", count: 0)
                    }
                }
                .listRowBackground(Color.row)
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("Tasks")
            .navigationDestination(for: String.self) { BoardView(boardId: $0) }
            .navigationDestination(for: TaskItem.self) { TaskDetailView(taskId: $0.id) }
            .navigationDestination(for: WebLink.self) { WebPageView(title: $0.title, path: $0.path) }
            .navigationDestination(for: TasksPage.self) { page in
                switch page {
                case .actions: ActionItemsView()
                case .archive: ArchiveView()
                case .timeline: SeasonTimelineView()
                }
            }
        }
    }
}

enum TasksPage: Hashable { case actions, archive, timeline }

struct BoardRow: View {
    let name: String
    let color: Color
    var systemImage: String?
    let count: Int
    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage ?? "square.grid.2x2.fill", color: color, size: 34)
            Text(name).font(.body.weight(.semibold))
            Spacer()
            if count > 0 { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
        }
        .padding(.vertical, 2)
    }
}

/// One board, a column at a time (swipe between them or tap the tabs). "mine" is My Work across every board.
struct BoardView: View {
    @Environment(AppModel.self) private var model
    let boardId: String
    @State private var columnId = ""
    @State private var onlyMine = false
    @State private var creating = false

    private var isMine: Bool { boardId == "mine" }
    private var board: Subteam? { model.subteam(boardId) }
    /// My Work shows the shared columns, plus a board-only one (Business's Grants) only when one of my tasks sits in it: boardColumns in mod-board.
    private var cols: [BoardColumn] {
        guard isMine else { return model.columns(for: boardId) }
        return model.columns(for: "all").filter { c in c.subteamIds.isEmpty || !tasks(in: c.id).isEmpty }
    }

    private func tasks(in col: String) -> [TaskItem] {
        model.tasks
            .filter { $0.columnId == col }
            .filter { isMine ? ($0.assigneeUids.contains(model.uid) || $0.backupUids.contains(model.uid)) : $0.subteamId == boardId }
            .filter { !onlyMine || $0.assigneeUids.contains(model.uid) }
            .sorted { $0.position < $1.position }
    }

    var body: some View {
        VStack(spacing: 0) {
            columnTabs
            // A paging scroll view, not a page-style TabView: that one kept pages it hadn't shown yet stale, so tapping
            // Grants on Business said "Nothing here." until you switched away and back.
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(cols) { c in
                        columnList(c).containerRelativeFrame(.horizontal).id(c.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: Binding(get: { columnId.isEmpty ? nil : columnId }, set: { if let id = $0 { columnId = id } }))
        }
        .appBackground()
        .navigationTitle(isMine ? "My Work" : board?.name ?? "Board")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isMine {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Only my tasks", isOn: $onlyMine)
                    } label: { Image(systemName: onlyMine ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }
                }
                if model.canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { creating = true } label: { Image(systemName: "plus") }
                    }
                }
            }
        }
        .sheet(isPresented: $creating) { NewTaskView(subteamId: boardId, columnId: columnId) }
        // Always on a column that exists, from the first frame and if columns change while it's open
        .onChange(of: cols.map(\.id)) { _, ids in if !ids.contains(columnId) { columnId = ids.contains("todo") ? "todo" : ids.first ?? "" } }
        .onAppear {
            if !cols.contains(where: { $0.id == columnId }) { columnId = cols.first { $0.id == "todo" }?.id ?? cols.first?.id ?? "" }
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-column"), i + 1 < args.count { columnId = args[i + 1] }
            #endif
        }
    }

    private var columnTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cols) { c in
                    let on = c.id == columnId
                    Button {
                        withAnimation(.snappy) { columnId = c.id }
                    } label: {
                        HStack(spacing: 6) {
                            Text(c.name)
                            Text("\(tasks(in: c.id).count)").foregroundStyle(on ? .white.opacity(0.8) : .secondary).monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(on ? .white : statusColor(c.id))
                        .background(on ? statusColor(c.id) : Color.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private func columnList(_ c: BoardColumn) -> some View {
        let list = tasks(in: c.id)
        return ScrollView {
            LazyVStack(spacing: 10) {
                if !model.loaded.contains("tasks") { SkeletonRows() }
                else if list.isEmpty {
                    Text(c.id == model.doneColumnId ? "Nothing finished yet." : "Nothing here.")
                        .foregroundStyle(.secondary).padding(.top, 40)
                }
                ForEach(list) { t in
                    NavigationLink(value: t) { TaskRow(task: t, showBoard: isMine) }
                        .buttonStyle(.plain)
                        .contextMenu { moveMenu(t) }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
    }

    @ViewBuilder private func moveMenu(_ t: TaskItem) -> some View {
        if model.canEdit {
            ForEach(model.columns(for: t.subteamId).filter { $0.id != t.columnId }) { c in
                Button { model.move(t, to: c.id) } label: { Label("Move to \(c.name)", systemImage: c.id == model.doneColumnId ? "checkmark.circle" : "arrow.right.circle") }
            }
            if model.canDelete(t) {
                Divider()
                Button(role: .destructive) {
                    model.archive(t)
                    model.toast = "Archived “\(t.title)”"
                } label: { Label("Archive", systemImage: "archivebox") }
            }
        }
    }
}

/// A symbol for each subteam's board.
func boardSymbol(_ id: String) -> String {
    switch id {
    case "prog": "chevron.left.forwardslash.chevron.right"
    case "elec": "bolt.fill"
    case "vision": "eye.fill"
    case "cad": "cube.fill"
    case "mech": "wrench.and.screwdriver.fill"
    case "biz": "briefcase.fill"
    case "media": "megaphone.fill"
    case "strat": "chart.xyaxis.line"
    case "drive": "steeringwheel"
    default: "square.grid.2x2.fill"
    }
}

/// Column headings take the status colour (the website's hover.dev-style boards).
func statusColor(_ columnId: String) -> Color {
    switch columnId {
    case "todo": .blue
    case "doing": .orange
    case "done": .green
    case "grants": .purple
    default: .teal
    }
}

/// A flat task card with a hairline, like the website's.
struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    var showBoard = false

    var body: some View {
        let done = model.isDone(task)
        let tint = model.subteam(task.subteamId)?.color ?? Brand.blue
        HStack(alignment: .top, spacing: 12) {
            // Tick it off right here (it moves to Done, like dragging on the board)
            Button {
                guard model.canEdit else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    model.move(task, to: done ? (model.columns(for: task.subteamId).first { $0.id == "todo" }?.id ?? "todo") : model.doneColumnId)
                }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : task.isGoal ? "flag.circle" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(done ? .green : tint)
                    .symbolEffect(.bounce, value: done)
            }
            .buttonStyle(.plain)
            .disabled(!model.canEdit)
            .accessibilityLabel(done ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(task.title).font(.body.weight(.semibold)).strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? .secondary : .primary).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if !task.assigneeUids.isEmpty { AvatarStack(ids: task.assigneeUids) }
                }
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    if showBoard, let s = model.subteam(task.subteamId) {
                        HStack(spacing: 5) { SubteamDot(color: s.color, size: 7); Text(s.name) }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    if task.priority == .high || task.priority == .critical { Pill(text: task.priority.label, systemImage: "exclamationmark", tint: task.priority.tint) }
                    DuePill(iso: task.dueDate, done: done)
                    if !task.checklist.isEmpty {
                        Pill(text: "\(task.checklist.filter(\.done).count)/\(task.checklist.count)", systemImage: "checklist")
                    }
                    if task.commentCount > 0 { Pill(text: "\(task.commentCount)", systemImage: "bubble.left.fill") }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(18, tint: done ? nil : tint)
        .contentShape(Rectangle())
    }
}

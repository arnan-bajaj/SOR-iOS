import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .notConfigured: NotConfiguredView()
            case .starting, .loadingProfile: LaunchView()
            case .signedOut: SignInView()
            case .onboarding: OnboardingView()
            case .pending: PendingView()
            case .ready: MainTabs()
            case .failed(let message): FailedView(message: message)
            }
        }
        .modifier(ToastModifier())
        .fontDesign(.rounded)
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }
}

struct LaunchView: View {
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                Image("Logo").resizable().scaledToFit().frame(width: 120, height: 120).clipShape(Circle())
                ProgressView()
            }
        }
    }
}

struct FailedView: View {
    @Environment(AppModel.self) private var model
    let message: String
    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Sign out") { model.signOut() }.buttonStyle(.bordered)
        }
        .appBackground()
    }
}

struct NotConfiguredView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Firebase isn't set up", systemImage: "gearshape.2")
        } description: {
            Text("This build has no GoogleService-Info.plist. Add it to the SOR folder in Xcode (see README, “One-time setup”), then build again.")
        }
        .appBackground()
    }
}

enum AppTab: Hashable { case home, tasks, create, meetings, you }

/// Home, Tasks, Create, Meetings, You: the same five tabs as the website on a phone.
struct MainTabs: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .home
    @State private var lastTab: AppTab = .home
    /// Bumped after each new task, so the Create tab starts empty next time.
    @State private var createRun = 0
    @State private var debugWeb: WebLink?
    @State private var helper = Helper()
    @State private var debugNative: String?

    var body: some View {
        TabView(selection: $tab) {
            HomeView(tab: $tab)
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(AppTab.home)
            TasksView()
                .tabItem { Label("Tasks", systemImage: "square.grid.3x2.fill") }.tag(AppTab.tasks)
            if model.canEdit {
                NewTaskView(onDone: { tab = lastTab; createRun += 1 })
                    .id(createRun)
                    .tabItem { Label("Create", systemImage: "plus.circle.fill") }.tag(AppTab.create)
            }
            MeetingsView()
                .tabItem { Label("Meetings", systemImage: "calendar") }.tag(AppTab.meetings)
            YouView()
                .tabItem { Label("You", systemImage: "person.crop.circle.fill") }.tag(AppTab.you)
        }
        // Create is a real tab (the new-task form), so the tab bar's glass lands on it instead of bouncing back
        // when a sheet opens. Cancel or Add goes back to where you were.
        .onChange(of: tab) { _, new in if new != .create { lastTab = new } }
        .sheet(item: Binding(get: { model.openLink }, set: { model.openLink = $0 })) { LinkSheet(link: $0) }
        .sheet(isPresented: Binding(get: { model.showHelper }, set: { model.showHelper = $0 })) { HelperView(helper: helper) }
        #if DEBUG
        // Test hooks for the Simulator: -tab meetings, -openWeb analytics, -openHelper
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
            if let t = arg("-tab") { tab = ["tasks": .tasks, "create": .create, "meetings": .meetings, "you": .you][t] ?? .home }
            if let w = arg("-openWeb") { debugWeb = WebLink(title: w, path: w) }
            if let n = arg("-openNative") { debugNative = n }
            if args.contains("-openHelper") { model.showHelper = true }
        }
        .sheet(item: $debugWeb) { link in NavigationStack { WebPageView(title: link.title, path: link.path) } }
        .fullScreenCover(item: Binding(get: { debugNative.map { WebLink(title: $0, path: $0) } }, set: { debugNative = $0?.path })) { l in
            NavigationStack {
                switch l.path {
                case "timeline": SeasonTimelineView()
                case "boardroom": BoardRoomView()
                case "analytics": AnalyticsView()
                case "actions": ActionItemsView()
                case "helper": HelperView(helper: Helper())
                case "reports": ReportsView()
                case "report": ReportSheet(target: ReportTarget(kind: "comment", path: "tasks/t0/comments/c1", taskId: "t0", authorUid: "u-sam", text: "Example"))
                case "biz": BoardView(boardId: "biz")
                case "mine": BoardView(boardId: "mine").navigationDestination(for: TaskItem.self) { TaskDetailView(taskId: $0.id) }
                default: TeamView()
                }
            }
        }
        #endif
    }
}

extension WebLink: Identifiable { var id: String { path } }

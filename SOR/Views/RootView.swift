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
    @State private var creating = false
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
                Color.clear
                    .tabItem { Label("Create", systemImage: "plus.circle.fill") }.tag(AppTab.create)
            }
            MeetingsView()
                .tabItem { Label("Meetings", systemImage: "calendar") }.tag(AppTab.meetings)
            YouView()
                .tabItem { Label("You", systemImage: "person.crop.circle.fill") }.tag(AppTab.you)
        }
        .onChange(of: tab) { old, new in
            // Create is an action, not a page: open the new-task sheet and stay where you were.
            if new == .create { tab = old; creating = true } else { lastTab = new }
        }
        .sheet(isPresented: $creating) { NewTaskView() }
        .sheet(item: Binding(get: { model.openLink }, set: { model.openLink = $0 })) { LinkSheet(link: $0) }
        .sheet(isPresented: Binding(get: { model.showHelper }, set: { model.showHelper = $0 })) { HelperView(helper: helper) }
        #if DEBUG
        // Test hooks for the Simulator: -tab meetings, -openWeb analytics
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
            if let t = arg("-tab") { tab = ["tasks": .tasks, "meetings": .meetings, "you": .you][t] ?? .home }
            if let w = arg("-openWeb") { debugWeb = WebLink(title: w, path: w) }
            if let n = arg("-openNative") { debugNative = n }
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
                case "biz": BoardView(boardId: "biz")
                default: TeamView()
                }
            }
        }
        #endif
    }
}

extension WebLink: Identifiable { var id: String { path } }

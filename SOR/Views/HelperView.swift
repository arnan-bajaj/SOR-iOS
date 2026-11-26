import SwiftUI

/// The helper's chat sheet. It opens from the sparkle button on Home (and You), never by itself.
struct HelperView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let helper: Helper
    @State private var text = ""
    /// Apple asks apps to get permission before sending personal data to an outside AI: once per person, on this phone.
    @State private var consented = false
    private var consentKey: String { "sor-helper-consent:\(model.uid)" }
    @FocusState private var typing: Bool

    private var suggestions: [String] {
        ["What's on my plate this week?", "When's the next hangar meeting?"]
            + (model.canEdit ? ["Add a task for me to…", "Mark one of my tasks done"] : ["What is the team working on?"])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if consented { intro } else { consent }
                            ForEach(helper.items) { item in row(item).id(item.id) }
                            if helper.busy {
                                HStack(spacing: 8) { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }.font(.subheadline).id("busy")
                            }
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: helper.items.count) { _, _ in withAnimation { proxy.scrollTo(helper.busy ? AnyHashable("busy") : AnyHashable(helper.items.last?.id), anchor: .bottom) } }
                    .onChange(of: helper.busy) { _, b in if b { withAnimation { proxy.scrollTo("busy", anchor: .bottom) } } }
                }
                if consented { composer }
            }
            .appBackground(Brand.violet)
            .navigationTitle("Helper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) { helper.clear() } label: { Label("Clear the chat", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            consented = UserDefaults.standard.bool(forKey: consentKey)
            helper.model = model
            helper.restore()
            helper.onOpen = { path in
                dismiss()
                Task { try? await Task.sleep(for: .milliseconds(450)); model.open(path: path) }
            }
        }
    }

    /// Before the first message: what goes to Google, and a clear yes or no. Short enough to fit the half-height sheet.
    private var consent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconTile(systemImage: "sparkles", color: Brand.violet, size: 30)
                Text("Before you use the helper").font(.headline)
            }
            Text("The helper runs on **Google Gemini**, outside the team. It sends Google what you type, your name, and the board's open tasks, people, upcoming meetings and action items.")
                .font(.subheadline)
            Text("Never emails, attendance, private answers or anything confidential. See the Privacy Policy.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("Not now") { model.showHelper = false }.buttonStyle(.bordered)
                Spacer()
                Button {
                    UserDefaults.standard.set(true, forKey: consentKey)
                    withAnimation { consented = true }
                } label: { Text("Allow").fontWeight(.semibold).frame(minWidth: 80) }
                .buttonStyle(.borderedProminent).tint(Brand.violet)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .glass(20, tint: Brand.violet)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconTile(systemImage: "sparkles", color: Brand.violet, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask about the board").font(.headline)
                    Text(model.canEdit ? "Or tell it what to change. Nothing changes until you tap Do it." : "Tasks, meetings, who's on what.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("This runs on the team's own Gemini key, so we ask that you don't misuse it. It can also get things wrong.")
                .font(.caption).foregroundStyle(.secondary)
            if !helper.off.isEmpty { Label(helper.off, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
            if helper.items.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button {
                            if s.hasSuffix("…") { text = String(s.dropLast()); typing = true } else { helper.send(s) }
                        } label: {
                            Text(s).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 7).glass(16, tint: Brand.violet)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .glass(20)
    }

    @ViewBuilder private func row(_ item: Helper.Item) -> some View {
        switch item {
        case .you(_, let t):
            HStack {
                Spacer(minLength: 50)
                Text(t).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Brand.wash(Brand.blue), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
        case .it(_, let t):
            HStack {
                Text((try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glass(18)
                Spacer(minLength: 40)
            }
        case .note(_, let t):
            Label(t, systemImage: "arrow.up.forward.app").font(.caption).foregroundStyle(.secondary)
        case .error(_, let t):
            Label(t, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange)
        case .card(let id):
            if let c = helper.cards[id] { card(id, c.plan, c.state) }
        }
    }

    private func card(_ id: UUID, _ plan: Helper.Plan, _ state: Helper.CardState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Brand.violet).tracking(0.5)
            Text(plan.head).font(.headline)
            ForEach(plan.lines.filter { !$0.isEmpty }, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
            switch state {
            case .ask:
                HStack {
                    Button("Not now") { helper.decide(id, false) }.buttonStyle(.bordered)
                    Spacer()
                    Button { helper.decide(id, true) } label: { Text("Do it").fontWeight(.semibold).frame(minWidth: 70) }.buttonStyle(.borderedProminent).tint(Brand.violet)
                }
                .padding(.top, 4)
            case .doing: ProgressView()
            case .done:
                HStack {
                    Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let p = plan.path { Button("Open") { helper.onOpen?(p) }.font(.subheadline) }
                }
            case .no: Label("You said no", systemImage: "xmark.circle").font(.subheadline).foregroundStyle(.secondary)
            case .failed(let msg): Label(msg, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(18, tint: Brand.violet)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(model.canEdit ? "Ask, or tell it what to do" : "Ask about the board", text: $text, axis: .vertical)
                .lineLimit(1...5).focused($typing)
                .padding(.horizontal, 14).padding(.vertical, 10).glass(20)
                .onSubmit(send)
            Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).symbolRenderingMode(.hierarchical).foregroundStyle(Brand.violet) }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func send() {
        let t = text
        text = ""
        helper.send(t)
    }
}

/// The small sparkle button that opens the helper.
struct HelperButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { model.showHelper = true } label: {
            Image(systemName: "sparkles").font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Brand.violet)
                .frame(width: 40, height: 40)
                .glass(20, tint: Brand.violet)
        }
        .accessibilityLabel("Helper")
    }
}

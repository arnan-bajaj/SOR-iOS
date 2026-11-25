import SwiftUI
import PhotosUI

/// A task's photos (up to 8, kept 14 days), like the website: see them, add from the camera roll, remove your own.
struct PhotosSection: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    let edit: Bool
    @State private var picks: [PhotosPickerItem] = []
    @State private var adding = false
    @State private var viewing: String?

    var body: some View {
        let live = task.photos.filter { $0.exp > Date().timeIntervalSince1970 * 1000 }
        Section {
            if !live.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(live, id: \.id) { p in
                            PhotoThumb(id: p.id).onTapGesture { viewing = p.id }
                                .contextMenu {
                                    if edit && (p.by == model.uid || model.isLead) {
                                        Button(role: .destructive) { Task { await model.removePhoto(task, p.id) } } label: { Label("Remove", systemImage: "trash") }
                                    }
                                }
                        }
                    }
                }
            }
            if edit && !model.demo {
                PhotosPicker(selection: $picks, maxSelectionCount: max(1, 8 - live.count), matching: .images) {
                    HStack { Label("Add photos", systemImage: "photo.on.rectangle.angled"); if adding { Spacer(); ProgressView() } }
                }
                .disabled(live.count >= 8 || adding)
            }
        } header: { Text("Photos") } footer: { Text("Photos last 14 days. Long-press one to remove it.") }
        .listRowBackground(Color.row)
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            adding = true
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        do { try await model.addPhoto(model.task(task.id) ?? task, img) } catch { model.toast = error.localizedDescription }
                    }
                }
                picks = []
                adding = false
            }
        }
        .sheet(item: Binding(get: { viewing.map { PhotoID(id: $0) } }, set: { viewing = $0?.id })) { p in
            PhotoFull(id: p.id)
        }
    }
}

private struct PhotoID: Identifiable { let id: String }

private struct PhotoThumb: View {
    @Environment(AppModel.self) private var model
    let id: String
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() } else { Rectangle().fill(.secondary.opacity(0.15)).overlay(ProgressView()) }
        }
        .frame(width: 92, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task { image = await model.photo(id) }
    }
}

private struct PhotoFull: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var image: UIImage?
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView() }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { image = await model.photo(id) }
        }
    }
}

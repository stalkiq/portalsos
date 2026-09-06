import SwiftUI
import UIKit

struct NoteItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var body: String
    var updatedAt: Date
    var imageFilename: String?

    init(id: UUID = UUID(), title: String, body: String, updatedAt: Date = Date(), imageFilename: String? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
        self.imageFilename = imageFilename
    }
}

@MainActor
final class NotesStore: ObservableObject {
    @Published var notes: [NoteItem] = []
    @Published var selectedID: UUID?

    private let storageKey = "portalsos.notes.v1"

    var selectedNote: NoteItem? {
        notes.first(where: { $0.id == selectedID }) ?? notes.first
    }

    var insightContext: String? {
        guard let note = selectedNote else { return nil }
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty && note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        var parts = ["The user has a Notes app open."]
        if !note.title.isEmpty {
            parts.append("Title: \(note.title)")
        }
        if !body.isEmpty {
            parts.append("Note text:\n\(String(body.prefix(3500)))")
        }
        if note.imageFilename != nil {
            parts.append("This note includes a photo captured from Camera.")
        }
        if notes.count > 1 {
            let others = notes.filter { $0.id != note.id }.prefix(6).map { $0.title.isEmpty ? "Untitled" : $0.title }
            parts.append("Other notes: \(others.joined(separator: ", "))")
        }
        return parts.joined(separator: "\n")
    }

    init() {
        load()
        if notes.isEmpty {
            let welcome = NoteItem(
                title: "Welcome",
                body: "Write ideas here. Close this app and drag Notes into Insight to summarize, extract tasks, or suggest a next step."
            )
            notes = [welcome]
            selectedID = welcome.id
            save()
        } else if selectedID == nil {
            selectedID = notes.first?.id
        }
    }

    func addNote() {
        let note = NoteItem(title: "New note", body: "")
        notes.insert(note, at: 0)
        selectedID = note.id
        save()
    }

    @discardableResult
    func addNote(title: String, body: String) -> NoteItem {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = NoteItem(
            title: trimmedTitle.isEmpty ? "Insight" : String(trimmedTitle.prefix(48)),
            body: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        notes.insert(note, at: 0)
        selectedID = note.id
        save()
        return note
    }

    @discardableResult
    func addNote(fromCameraImage image: UIImage, insight: String) -> NoteItem {
        let noteID = UUID()
        let filename = "\(noteID.uuidString).jpg"
        if let data = image.jpegData(compressionQuality: 0.82) {
            let url = imagesDirectory().appendingPathComponent(filename)
            try? FileManager.default.createDirectory(at: imagesDirectory(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        let note = NoteItem(
            id: noteID,
            title: Self.title(fromInsight: insight),
            body: insight,
            imageFilename: filename
        )
        notes.insert(note, at: 0)
        selectedID = note.id
        save()
        return note
    }

    func image(for note: NoteItem) -> UIImage? {
        guard let filename = note.imageFilename else { return nil }
        let url = imagesDirectory().appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    func updateSelected(title: String, body: String) {
        guard let selectedID, let index = notes.firstIndex(where: { $0.id == selectedID }) else { return }
        notes[index].title = title
        notes[index].body = body
        notes[index].updatedAt = Date()
        save()
    }

    func deleteSelected() {
        guard let selectedID else { return }
        if let note = notes.first(where: { $0.id == selectedID }), let filename = note.imageFilename {
            let url = imagesDirectory().appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }
        notes.removeAll { $0.id == selectedID }
        self.selectedID = notes.first?.id
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([NoteItem].self, from: data) else {
            return
        }
        notes = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func imagesDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NoteImages", isDirectory: true)
    }

    private static func title(fromInsight insight: String) -> String {
        let line = insight
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if line.isEmpty {
            return "Camera note"
        }
        return String(line.prefix(48))
    }
}

struct NotesAppView: View {
    @ObservedObject var store: NotesStore
    @Environment(\.dismiss) private var dismiss
    @State private var titleText = ""
    @State private var bodyText = ""
    @State private var keyboardOverlap: CGFloat = 0
    @FocusState private var notesFocus: NotesField?

    private enum NotesField: Hashable {
        case title, body
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Close") {
                    notesFocus = nil
                    Keyboard.dismiss()
                    dismiss()
                }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Notes")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
                Button("New", action: addNote)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if store.selectedNote != nil {
                    Button("Delete", role: .destructive, action: store.deleteSelected)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.07, green: 0.08, blue: 0.12))

            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.notes) { note in
                            Button {
                                notesFocus = nil
                                Keyboard.dismiss()
                                persistCurrent()
                                store.selectedID = note.id
                                loadSelected()
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    if let image = store.image(for: note) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 36, height: 36)
                                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(note.title.isEmpty ? "Untitled" : note.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.94))
                                            .lineLimit(1)
                                        Text(note.body.isEmpty ? "Empty note" : note.body)
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundStyle(.white.opacity(0.62))
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(
                                    Color.white.opacity(store.selectedID == note.id ? 0.14 : 0.06),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
                .dismissesKeyboardOnScroll()
                .frame(width: 148)

                Divider().overlay(Color.white.opacity(0.12))

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let selected = store.selectedNote, let image = store.image(for: selected) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: keyboardOverlap > 0 ? 72 : 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        TextField("Title", text: $titleText)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .focused($notesFocus, equals: .title)
                            .submitLabel(.next)
                            .onSubmit { notesFocus = .body }
                        TextEditor(text: $bodyText)
                            .font(.system(size: 16, weight: .regular))
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(.white.opacity(0.92))
                            .focused($notesFocus, equals: .body)
                            .frame(minHeight: 220)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .padding(.bottom, max(24, keyboardOverlap))
                }
                .dismissesKeyboardOnScroll()
            }
        }
        .background(Color(red: 0.06, green: 0.07, blue: 0.11).ignoresSafeArea(.container))
        .keyboardDoneButton()
        .readsKeyboardOverlap($keyboardOverlap)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: loadSelected)
        .onChange(of: titleText) { _, _ in persistCurrent() }
        .onChange(of: bodyText) { _, _ in persistCurrent() }
        .onDisappear(perform: persistCurrent)
        }
    }

    private func loadSelected() {
        titleText = store.selectedNote?.title ?? ""
        bodyText = store.selectedNote?.body ?? ""
    }

    private func persistCurrent() {
        store.updateSelected(title: titleText, body: bodyText)
    }

    private func addNote() {
        persistCurrent()
        store.addNote()
        loadSelected()
    }
}

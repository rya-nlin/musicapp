//
//  ContentView.swift
//  music app
//
//  Created by Ryan Lin on 5/8/25.
//
import SwiftUI
import MusicKit

struct AlbumFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var albumKeys: [String] = [] // ordered front-to-back; front = index 0

    init(id: UUID = UUID(), name: String, albumKeys: [String] = []) {
        self.id = id
        self.name = name
        self.albumKeys = albumKeys
    }
}

@MainActor
final class MusicLibraryStore: ObservableObject {
    @Published var status: MusicAuthorization.Status = .notDetermined
    @Published var albums: [Album] = []
    @Published var folders: [AlbumFolder] = []
    @Published var statusMessage: String = "No album playing"

    private let player = ApplicationMusicPlayer.shared
    private let foldersDefaultsKey = "music_app_folders"

    func bootstrap() async {
        loadSavedFolders()
        status = await MusicAuthorization.request()
        if status == .authorized {
            await loadAlbums()
        } else {
            statusMessage = "Apple Music access not granted"
        }
    }

    func loadAlbums() async {
        do {
            let request = MusicLibraryRequest<Album>()
            let response = try await request.response()
            albums = Array(response.items)
            statusMessage = albums.isEmpty ? "No albums found" : "Loaded \(albums.count) albums"
        } catch {
            statusMessage = "Library error: \(error.localizedDescription)"
        }
    }

    // MARK: - Folders

    func createFolder(named rawName: String) {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        folders.append(AlbumFolder(name: trimmedName))
        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveFolders()
    }

    func deleteFolders(at offsets: IndexSet) {
        folders.remove(atOffsets: offsets)
        saveFolders()
    }

    func folderID(for album: Album) -> UUID? {
        let key = albumKey(for: album)
        return folders.first(where: { $0.albumKeys.contains(key) })?.id
    }

    func assign(_ album: Album, to folderID: UUID) {
        let key = albumKey(for: album)
        for index in folders.indices {
            folders[index].albumKeys.removeAll { $0 == key }
        }
        if let index = folders.firstIndex(where: { $0.id == folderID }) {
            folders[index].albumKeys.append(key)
        }
        saveFolders()
    }

    func unassign(_ album: Album) {
        let key = albumKey(for: album)
        for index in folders.indices {
            folders[index].albumKeys.removeAll { $0 == key }
        }
        saveFolders()
    }

    func moveAlbum(in folderID: UUID, from source: IndexSet, to destination: Int) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].albumKeys.move(fromOffsets: source, toOffset: destination)
        saveFolders()
    }

    func removeAlbum(at offsets: IndexSet, from folderID: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].albumKeys.remove(atOffsets: offsets)
        saveFolders()
    }

    func albumCount(in folder: AlbumFolder) -> Int {
        folder.albumKeys.count
    }

    /// Albums in the folder's stored order, front to back.
    func orderedAlbums(in folder: AlbumFolder) -> [Album] {
        let albumsByKey = Dictionary(uniqueKeysWithValues: albums.map { (albumKey(for: $0), $0) })
        return folder.albumKeys.compactMap { albumsByKey[$0] }
    }

    // MARK: - Playback

    func play(album: Album) async {
        guard status == .authorized else { return }
        do {
            player.queue = ApplicationMusicPlayer.Queue(for: [album])
            try await player.play()
            statusMessage = "Playing \(album.title)"
        } catch {
            statusMessage = "Playback error: \(error.localizedDescription)"
        }
    }

    /// Plays every album in the folder back-to-back, each album in its own track order.
    /// `shuffled` only shuffles the order of the albums, never the tracks within an album.
    func playFolder(_ folder: AlbumFolder, shuffled: Bool) async {
        guard status == .authorized else { return }
        var queueAlbums = orderedAlbums(in: folder)
        guard !queueAlbums.isEmpty else {
            statusMessage = "No albums in \(folder.name)"
            return
        }

        if shuffled {
            queueAlbums.shuffle()
        }

        do {
            player.queue = ApplicationMusicPlayer.Queue(for: queueAlbums)
            try await player.play()
            statusMessage = "\(shuffled ? "Shuffling" : "Playing") \(folder.name): \(queueAlbums.count) albums"
        } catch {
            statusMessage = "Playback error: \(error.localizedDescription)"
        }
    }

    func skip() async {
        guard status == .authorized else { return }
        do {
            try await player.skipToNextEntry()
        } catch {
            statusMessage = "Skip error: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    private func albumKey(for album: Album) -> String {
        album.id.rawValue
    }

    private func loadSavedFolders() {
        guard let data = UserDefaults.standard.data(forKey: foldersDefaultsKey),
              let decoded = try? JSONDecoder().decode([AlbumFolder].self, from: data) else { return }
        folders = decoded
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: foldersDefaultsKey)
    }
}

struct ContentView: View {
    @StateObject private var store = MusicLibraryStore()
    @State private var showingCreateFolderAlert = false
    @State private var newFolderName = ""

    var body: some View {
        TabView {
            NavigationStack {
                Group {
                    if store.status == .authorized {
                        LibraryGridView(store: store)
                    } else {
                        unauthorizedView
                    }
                }
                .navigationTitle("Library")
            }
            .tabItem { Label("Library", systemImage: "square.grid.2x2") }

            NavigationStack {
                Group {
                    if store.status == .authorized {
                        FoldersListView(store: store)
                    } else {
                        unauthorizedView
                    }
                }
                .navigationTitle("Folders")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            newFolderName = ""
                            showingCreateFolderAlert = true
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    }
                }
                .alert("New Folder", isPresented: $showingCreateFolderAlert) {
                    TextField("Folder name", text: $newFolderName)
                    Button("Create") { store.createFolder(named: newFolderName) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Create a folder to organize albums from your library.")
                }
            }
            .tabItem { Label("Folders", systemImage: "folder") }
        }
        .safeAreaInset(edge: .bottom) {
            if store.status == .authorized {
                PlayerStatusBar(store: store)
            }
        }
        .task {
            await store.bootstrap()
        }
    }

    private var unauthorizedView: some View {
        Text("Authorize Apple Music access to load your library.")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
    }
}

struct PlayerStatusBar: View {
    @ObservedObject var store: MusicLibraryStore

    var body: some View {
        HStack {
            Text(store.statusMessage)
                .font(.footnote)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await store.skip() }
            } label: {
                Image(systemName: "forward.fill")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AlbumArtworkView: View {
    let artwork: Artwork?
    var size: CGFloat = 160

    var body: some View {
        Group {
            if let artwork, let url = artwork.url(width: Int(size * 2), height: Int(size * 2)) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.08))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.08)
            .fill(Color.secondary.opacity(0.2))
            .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
    }
}

struct LibraryGridView: View {
    @ObservedObject var store: MusicLibraryStore

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            if store.albums.isEmpty {
                Text("No albums found in your library.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(store.albums, id: \.id) { album in
                        AlbumGridCell(store: store, album: album)
                    }
                }
                .padding()
            }
        }
    }
}

struct AlbumGridCell: View {
    @ObservedObject var store: MusicLibraryStore
    let album: Album

    var body: some View {
        Button {
            Task { await store.play(album: album) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                AlbumArtworkView(artwork: album.artwork, size: 160)
                Text(album.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(album.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            addToFolderMenu
        }
    }

    @ViewBuilder
    private var addToFolderMenu: some View {
        if store.folders.isEmpty {
            Text("No folders yet")
        } else {
            ForEach(store.folders) { folder in
                Button {
                    store.assign(album, to: folder.id)
                } label: {
                    if store.folderID(for: album) == folder.id {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }
            if store.folderID(for: album) != nil {
                Divider()
                Button("Remove from Folder", role: .destructive) {
                    store.unassign(album)
                }
            }
        }
    }
}

struct FoldersListView: View {
    @ObservedObject var store: MusicLibraryStore

    var body: some View {
        List {
            if store.folders.isEmpty {
                Text("No folders yet. Tap + to create one.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.folders) { folder in
                    NavigationLink(value: folder.id) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                            Text(folder.name)
                            Spacer()
                            Text("\(store.albumCount(in: folder))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: store.deleteFolders)
            }
        }
        .navigationDestination(for: UUID.self) { folderID in
            FolderDetailView(store: store, folderID: folderID)
        }
    }
}

struct FolderDetailView: View {
    @ObservedObject var store: MusicLibraryStore
    let folderID: UUID

    private var folder: AlbumFolder? {
        store.folders.first(where: { $0.id == folderID })
    }

    var body: some View {
        Group {
            if let folder {
                let orderedAlbums = store.orderedAlbums(in: folder)
                List {
                    Section {
                        HStack {
                            Button {
                                Task { await store.playFolder(folder, shuffled: false) }
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                Task { await store.playFolder(folder, shuffled: true) }
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .disabled(orderedAlbums.isEmpty)
                    }

                    Section("Albums") {
                        if orderedAlbums.isEmpty {
                            Text("No albums in this folder yet. Add some from the Library tab.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(orderedAlbums, id: \.id) { album in
                                Button {
                                    Task { await store.play(album: album) }
                                } label: {
                                    HStack {
                                        AlbumArtworkView(artwork: album.artwork, size: 50)
                                        VStack(alignment: .leading) {
                                            Text(album.title).font(.body)
                                            Text(album.artistName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .onMove { source, destination in
                                store.moveAlbum(in: folder.id, from: source, to: destination)
                            }
                            .onDelete { offsets in
                                store.removeAlbum(at: offsets, from: folder.id)
                            }
                        }
                    }
                }
                .navigationTitle(folder.name)
                .toolbar { EditButton() }
            } else {
                Text("Folder not found")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
}

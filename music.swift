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

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
struct MusicAuthorizationQuery
{
    static func request() async -> MusicAuthorization.Status{
        return await MusicAuthorization.request()
    }
}
//access user apple music library
func getAlbums() async {
    do{
        let request = MusicLibraryRequest<Album>() //fetch all albums in user library
        let response = try await request.response()
        for album in response.items{
            print(album.title)
        }
    }catch{}
}
//function gets albums from the user's library
struct ContentView: View {
    @State private var status: MusicAuthorization.Status = .notDetermined
    @State private var currentAlbum: String = "No album playing"
    @State private var albums: [Album] = []
    @State private var folders: [AlbumFolder] = []
    @State private var assignments: [String: UUID] = [:]
    @State private var selectedFolderID: UUID?
    @State private var showingCreateFolderAlert = false
    @State private var newFolderName = ""
    //creating state variables - local within view
    @AppStorage("music_app_folders") private var storedFolders = ""
    @AppStorage("music_app_album_folder_assignments") private var storedAssignments = ""
    //appstorage variables retain when closing app
    private let player = ApplicationMusicPlayer.shared
    var filteredAlbums: [Album] {
        guard let selectedFolderID else { return albums }
        return albums.filter { assignments[albumKey(for: $0)] == selectedFolderID }
    } //filteredalbums returns list of albums in a folder
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(currentAlbum)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Picker("Folder", selection: $selectedFolderID) {
                    Text("All Albums").tag(UUID?.none)
                    ForEach(folders) { folder in
                        Text(folder.name).tag(Optional(folder.id))
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("Play Random Album") {
                        Task {
                            await playRandomAlbum()
                        }
                    }
                    .disabled(status != .authorized || filteredAlbums.isEmpty)

                    Button("Skip Album") {
                        Task {
                            await skipAlbum()
                        }
                    }
                    .disabled(status != .authorized)
                }

                Button("Create Folder") {
                    newFolderName = ""
                    showingCreateFolderAlert = true
                }
                .disabled(status != .authorized)

                if status == .authorized {
                    List {
                        if !folders.isEmpty {
                            Section("Folders") {
                                ForEach(folders) { folder in
                                    HStack {
                                        Text(folder.name)
                                        Spacer()
                                        Text("\(albumCount(in: folder))")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .onDelete(perform: deleteFolders)
                            }
                        }

                        Section(selectedFolderID == nil ? "All Albums" : "Albums In Folder") {
                            if filteredAlbums.isEmpty {
                                Text(emptyStateMessage)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(filteredAlbums, id: \.id) { album in
                                    albumRow(for: album)
                                }
                            }
                        }
                    }
                } else {
                    Text("Authorize Apple Music access to load your library.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .navigationTitle("Music Folders")
        }
        .task {
            loadSavedData()
            status = await MusicAuthorization.request()
            if status == .authorized {
                await loadAlbums()
            } else {
                currentAlbum = "Apple Music access not granted"
            }
        }
        .alert("New Folder", isPresented: $showingCreateFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                createFolder()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a folder to organize albums from your library.")
        }
    }
    
 @ViewBuilder
    private func albumRow(for album: Album) -> some View {
        let key = albumKey(for: album)
        let assignedFolderID = assignments[key]
        let assignedFolderName = folders.first(where: { $0.id == assignedFolderID })?.name ?? "No folder"

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.headline)
                Text(album.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(assignedFolderName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Menu("Move") {
                Button("No Folder") {
                    unassignAlbum(album)
                }

                ForEach(folders) { folder in
                    Button(folder.name) {
                        assignAlbum(album, to: folder.id)
                    }
                }
            }
        }
    }
  private var emptyStateMessage: String {
        if albums.isEmpty {
            return "No albums found in your library."
        }
        if selectedFolderID != nil {
            return "No albums in this folder yet."
        }
        return "No albums available."
    }

    private func loadAlbums() async {
        do {
            let request = MusicLibraryRequest<Album>()
            let response = try await request.response()
            albums = Array(response.items)
            currentAlbum = albums.isEmpty ? "No albums found" : "Loaded \(albums.count) albums"
        } catch {
            currentAlbum = "Library error: \(error.localizedDescription)"
        }
    }

    func playRandomAlbumQueue(count: Int) async {
        guard status == .authorized else { return }
        
        do {
            let request = MusicLibraryRequest<Album>()
            let response = try await request.response()
            
            guard !response.items.isEmpty else {
                currentAlbum = "No albums found"
                return
            }
            
            // Shuffle and take up to 'count' albums (no duplicates)
            let randomAlbums = Array(response.items.shuffled().prefix(count))
            
            player.queue = ApplicationMusicPlayer.Queue(for: randomAlbums)
            try await player.play()
            
            currentAlbum = "Queue: \(randomAlbums.count) albums, starting with \(randomAlbums[0].title)"
        } catch {
            currentAlbum = "Queue error: \(error.localizedDescription)"
        }
    }
    func skipAlbum() async {
        guard status == .authorized else {return}
        do{
            try await player.skipToNextEntry()
        } catch {
            print("skip error",error)
        }
        
    }
      private func createFolder() {
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        folders.append(AlbumFolder(name: trimmedName))
        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveFolders()
    }

    private func deleteFolders(at offsets: IndexSet) {
        let idsToDelete = offsets.map { folders[$0].id }

        for folderID in idsToDelete {
            assignments = assignments.filter { $0.value != folderID }
            if selectedFolderID == folderID {
                selectedFolderID = nil
            }
        }

        folders.remove(atOffsets: offsets)
        saveFolders()
        saveAssignments()
    }

    private func assignAlbum(_ album: Album, to folderID: UUID) {
        assignments[albumKey(for: album)] = folderID
        saveAssignments()
    }

    private func unassignAlbum(_ album: Album) {
        assignments.removeValue(forKey: albumKey(for: album))
        saveAssignments()
    }
  private func albumCount(in folder: AlbumFolder) -> Int {
        albums.filter { assignments[albumKey(for: $0)] == folder.id }.count
    }

    private func albumKey(for album: Album) -> String {
        "\(album.title.lowercased())|\(album.artistName.lowercased())"
    }

    private func loadSavedData() {
        folders = decode([AlbumFolder].self, from: storedFolders) ?? []

        if let rawAssignments = decode([String: String].self, from: storedAssignments) {
            assignments = rawAssignments.reduce(into: [:]) { partialResult, item in
                if let uuid = UUID(uuidString: item.value) {
                    partialResult[item.key] = uuid
                }
            }
        }
    }

    private func saveFolders() {
        storedFolders = encode(folders)
    }

    private func saveAssignments() {
        let rawAssignments = assignments.mapValues(\.uuidString)
        storedAssignments = encode(rawAssignments)
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
    private func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
#Preview {
    ContentView()
}

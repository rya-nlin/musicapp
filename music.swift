//
//  ContentView.swift
//  music app
//
//  Created by Ryan Lin on 5/8/25.
//rn it js has a button and plays a random album from users apple music library
import SwiftUI
import MusicKit

struct MusicAuthorizationQuery
{
    static func request() async -> MusicAuthorization.Status{
        return await MusicAuthorization.request()
    }
}
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
    let player = ApplicationMusicPlayer.shared
    var body : some View{
        VStack(spacing: 20) {
            Button("Play Random Album") {
                Task {
                    await playRandomAlbumQueue(count: 3)
                }
            }
            .disabled(status != .authorized)
        }
        .task {
            status = await MusicAuthorization.request()
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
}
#Preview {
    ContentView()
}

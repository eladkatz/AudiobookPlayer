import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea(.all, edges: .all)
            
            TabView(selection: $selectedTab) {
                LibraryView(appState: appState)
                    .tabItem {
                        Label("Library", systemImage: "books.vertical")
                    }
                    .tag(0)
                
                PlayerView(appState: appState)
                    .tabItem {
                        Label("Now Playing", systemImage: "play.circle.fill")
                    }
                    .tag(1)
                
                SettingsView(appState: appState)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(2)
            }
            .ignoresSafeArea(.keyboard)
        }
        .onChange(of: appState.currentBook) { oldValue, newBook in
            // Auto-switch to player when a book is selected
            if newBook != nil && selectedTab != 1 {
                selectedTab = 1
            }
        }
        .onChange(of: appState.books) { oldValue, newValue in
            // Save books whenever the list changes
            PersistenceManager.shared.saveBooks(newValue)
        }
        .onChange(of: appState.currentBook?.id) { oldValue, bookID in
            // Save current book ID
            PersistenceManager.shared.saveCurrentBookID(bookID)
        }
        .onReceive(AudioManager.shared.$currentTime) { time in
            // Update book position
            if var book = appState.currentBook {
                book.currentPosition = time
                appState.currentBook = book
                PersistenceManager.shared.savePosition(for: book.id, position: time)
            }
        }
    }
}


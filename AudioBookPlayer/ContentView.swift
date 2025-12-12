import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var audioManager = AudioManager.shared
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
            
            // Full-screen sleep timer overlay at ContentView level
            if audioManager.isSleepTimerActive {
                SleepTimerFullScreenView(audioManager: audioManager)
                    .transition(.opacity)
                    .zIndex(1000)
                    .ignoresSafeArea(.all, edges: .all)
            }
            
            // Interruption toast notification
            if audioManager.showInterruptionToast {
                InterruptionToastView(message: audioManager.interruptionToastMessage)
                    .zIndex(999)
                    .ignoresSafeArea(.all, edges: .all)
            }
        }
        .onChange(of: appState.currentBook?.id) { oldID, newID in
            // Auto-switch to player when a book is selected (from library or elsewhere)
            if newID != nil && newID != oldID {
                // Use DispatchQueue to ensure the state change happens after the current update cycle
                DispatchQueue.main.async {
                    selectedTab = 1
                }
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
            // Update book position in both currentBook and books array
            if var book = appState.currentBook {
                book.currentPosition = time
                appState.currentBook = book
                
                // Also update the book in the books array so LibraryView shows current progress
                if let index = appState.books.firstIndex(where: { $0.id == book.id }) {
                    appState.books[index].currentPosition = time
                }
                
                // Save to persistence (throttled - only save every 5 seconds to avoid excessive writes)
                PersistenceManager.shared.savePosition(for: book.id, position: time)
            }
        }
    }
}


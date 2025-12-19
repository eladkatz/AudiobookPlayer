import SwiftUI

@main
struct AudioBookPlayerApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    loadInitialData()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func loadInitialData() {
        // Check Google Drive authentication status
        GoogleDriveManager.shared.checkAuthenticationStatus()
        
        // Load books
        appState.books = PersistenceManager.shared.loadBooks()
        
        // Load settings
        appState.playbackSettings = PersistenceManager.shared.loadSettings()
        
        // Load current book
        if let currentBookID = PersistenceManager.shared.loadCurrentBookID(),
           let book = appState.books.first(where: { $0.id == currentBookID }) {
            var updatedBook = book
            updatedBook.currentPosition = PersistenceManager.shared.loadPosition(for: book.id)
            appState.currentBook = updatedBook
        }
        
        // Retry failed cover downloads in background
        Task {
            let downloadedCovers = await CoverImageManager.shared.retryFailedDownloads(for: appState.books)
            
            // Update books with newly downloaded covers
            await MainActor.run {
                var updatedBooks = appState.books
                var hasChanges = false
                let currentBookID: UUID? = appState.currentBook?.id
                
                for (index, book) in updatedBooks.enumerated() {
                    if let coverURL = downloadedCovers[book.id] {
                        updatedBooks[index].coverImageURL = coverURL
                        hasChanges = true
                    }
                }
                
                if hasChanges {
                    appState.books = updatedBooks
                    PersistenceManager.shared.saveBooks(updatedBooks)
                    
                    // Update currentBook if it matches one of the updated books
                    if let currentID = currentBookID,
                       let updatedCurrentBook = updatedBooks.first(where: { $0.id == currentID }) {
                        var updatedCurrent = updatedCurrentBook
                        // Preserve the current position that was loaded earlier
                        updatedCurrent.currentPosition = appState.currentBook?.currentPosition ?? 0
                        appState.currentBook = updatedCurrent
                    }
                }
            }
        }
        
    }
}


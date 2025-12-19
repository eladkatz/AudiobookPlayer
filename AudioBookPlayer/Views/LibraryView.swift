import SwiftUI

struct LibraryView: View {
    @ObservedObject var appState: AppState
    @State private var showingImportSheet = false
    @State private var bookToDelete: Book?
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            List {
                if appState.books.isEmpty {
                    emptyStateView
                } else {
                    ForEach(appState.books) { book in
                        BookRow(book: book, appState: appState)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectBook(book)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    bookToDelete = book
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { indexSet in
                        // For swipe-to-delete gesture - delete multiple books
                        let booksToDelete = indexSet.map { appState.books[$0] }
                        for book in booksToDelete {
                            deleteBook(book, showConfirmation: false)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingImportSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportView(appState: appState)
            }
            .confirmationDialog(
                "Delete Book",
                isPresented: $showingDeleteConfirmation,
                presenting: bookToDelete
            ) { book in
                Button("Delete", role: .destructive) {
                    performBookDeletion(book)
                    bookToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    bookToDelete = nil
                }
            } message: { book in
                Text("Are you sure you want to delete \"\(book.title)\"? This will also delete all downloaded files.")
            }
        }
        .navigationViewStyle(.stack)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Books")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap the + button to import books")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Actions
    private func selectBook(_ book: Book) {
        // Update position from persistence
        let savedPosition = PersistenceManager.shared.loadPosition(for: book.id)
        var updatedBook = book
        updatedBook.currentPosition = savedPosition
        
        // Set current book first to trigger tab switch
        appState.currentBook = updatedBook
        
        // Load and start playback
        AudioManager.shared.loadBook(updatedBook)
        AudioManager.shared.play()
    }
    
    private func deleteBook(_ book: Book, showConfirmation: Bool = true) {
        if showConfirmation {
            bookToDelete = book
            showingDeleteConfirmation = true
            return
        }
        
        // Perform actual deletion
        performBookDeletion(book)
    }
    
    private func performBookDeletion(_ book: Book) {
        // Delete files from disk
        let fileManager = FileManager.default
        
        // Delete the main M4B file
        if fileManager.fileExists(atPath: book.fileURL.path) {
            try? fileManager.removeItem(at: book.fileURL)
        }
        
        // Delete cover image if it exists
        if let coverURL = book.coverImageURL,
           fileManager.fileExists(atPath: coverURL.path) {
            try? fileManager.removeItem(at: coverURL)
        }
        
        // Delete associated files (CUE, NFO, etc.)
        for associatedFile in book.associatedFiles {
            if fileManager.fileExists(atPath: associatedFile.path) {
                try? fileManager.removeItem(at: associatedFile)
            }
        }
        
        // If this is a Google Drive book, delete the entire folder
        if let folderID = book.googleDriveFileID {
            let booksDir = BookFileManager.shared.getBooksDirectory()
            let bookFolder = booksDir.appendingPathComponent(folderID)
            if fileManager.fileExists(atPath: bookFolder.path) {
                try? fileManager.removeItem(at: bookFolder)
            }
        }
        
        // Remove from app state
        appState.books.removeAll { $0.id == book.id }
        
        // Clear current book if it's the one being deleted
        if appState.currentBook?.id == book.id {
            appState.currentBook = nil
        }
        
        // Save updated books list
        PersistenceManager.shared.saveBooks(appState.books)
        
        bookToDelete = nil
    }
}

// MARK: - Book Row
struct BookRow: View {
    let book: Book
    @ObservedObject var appState: AppState
    
    private func statusBadge(for book: Book) -> some View {
        let status: (text: String, color: Color)
        
        if book.duration > 0 {
            let progress = book.currentPosition / book.duration
            if progress >= 0.99 {
                status = ("Done", .green)
            } else if book.currentPosition > 0 {
                status = ("In-Progress", .blue)
            } else {
                status = ("Started", .orange)
            }
        } else {
            status = ("Started", .orange)
        }
        
        return Text(status.text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color)
            .cornerRadius(4)
    }
    
    private func calculateChapterProgress() -> (currentChapter: Int, totalChapters: Int, progress: Double) {
        guard book.duration > 0 else {
            return (0, 0, 0.0)
        }
        
        let settings = appState.playbackSettings
        let chapterLength = settings.simulatedChapterLength
        
        // Calculate total chapters
        let totalChapters = max(1, Int(ceil(book.duration / chapterLength)))
        
        // Calculate current chapter (1-based)
        let currentChapter = min(totalChapters, max(1, Int(floor(book.currentPosition / chapterLength)) + 1))
        
        // Calculate progress within current chapter
        let chapterStartTime = Double(currentChapter - 1) * chapterLength
        let chapterProgress = min(1.0, max(0.0, (book.currentPosition - chapterStartTime) / chapterLength))
        
        // Overall chapter progress (which chapter we're on out of total)
        let overallProgress = Double(currentChapter - 1) / Double(totalChapters) + (chapterProgress / Double(totalChapters))
        
        return (currentChapter, totalChapters, overallProgress)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Cover Image
            Group {
                if let coverURL = book.coverImageURL,
                   let image = UIImage(contentsOfFile: coverURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .overlay(
                            Image(systemName: "book.closed.fill")
                                .foregroundColor(.gray)
                        )
                }
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)
            
            // Title and Author
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let author = book.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Progress section - Split into Left and Right
            HStack(alignment: .center, spacing: 12) {
                // Left: Status badge
                statusBadge(for: book)
                
                // Right: Chapter progress (two lines)
                if book.duration > 0 {
                    let chapterInfo = calculateChapterProgress()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        // Top: Progress bar
                        ProgressView(value: chapterInfo.progress, total: 1.0)
                            .frame(width: 60, height: 4)
                            .tint(.blue)
                        
                        // Bottom: Chapter text
                        Text("Chapter \(chapterInfo.currentChapter)/\(chapterInfo.totalChapters)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: 0, total: 1.0)
                            .frame(width: 60, height: 4)
                            .tint(.blue)
                        
                        Text("Duration unknown")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes))"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Import View
struct ImportView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var showingDocumentPicker = false
    @State private var showingGoogleDrivePicker = false
    @State private var isImporting = false
    @ObservedObject private var driveManager = GoogleDriveManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Import Books")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Import M4B files from your device")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 16) {
                    Button(action: {
                        showingDocumentPicker = true
                    }) {
                        HStack {
                            Image(systemName: "folder")
                            Text("Import from Files")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isImporting)
                    
                    Button(action: {
                        showingGoogleDrivePicker = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "icloud.and.arrow.down")
                            Text("Import from Google Drive")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    .disabled(isImporting)
                }
                .padding()
                
                if isImporting {
                    VStack(spacing: 16) {
                        // Circular progress indicator with percentage
                        ZStack {
                            Circle()
                                .stroke(Color(.systemGray5), lineWidth: 8)
                            
                            Circle()
                                .trim(from: 0, to: driveManager.downloadProgress)
                                .stroke(
                                    Color.blue,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.1), value: driveManager.downloadProgress)
                            
                            VStack(spacing: 4) {
                                Text("\(Int(driveManager.downloadProgress * 100))%")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text("Downloaded")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 100, height: 100)
                        
                        if !driveManager.currentDownloadFile.isEmpty {
                            VStack(spacing: 4) {
                                Text("Downloading:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(driveManager.currentDownloadFile)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                        } else {
                            Text("Importing...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(isPresented: $showingDocumentPicker) { url in
                    importBook(from: url)
                }
            }
            .sheet(isPresented: $showingGoogleDrivePicker) {
                GoogleDrivePickerView { m4bFileID, folderID in
                    importBookFromGoogleDriveM4B(m4bFileID: m4bFileID, folderID: folderID)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func importBook(from url: URL) {
        isImporting = true
        
        Task {
            if let book = await BookFileManager.shared.importBook(from: url) {
                await MainActor.run {
                    appState.books.append(book)
                    
                    // If cover was found during import, update the book before saving
                    if let coverURL = book.coverImageURL {
                        if let index = appState.books.firstIndex(where: { $0.id == book.id }) {
                            appState.books[index].coverImageURL = coverURL
                        }
                    }
                    
                    PersistenceManager.shared.saveBooks(appState.books)
                    isImporting = false
                    dismiss()
                }
                
                // Transcription will happen automatically when user enters a chapter
            } else {
                await MainActor.run {
                    isImporting = false
                    // Could show an error alert here
                }
            }
        }
    }
    
    private func importBookFromGoogleDriveM4B(m4bFileID: String, folderID: String) {
        isImporting = true
        
        Task {
            if let book = await BookFileManager.shared.importBookFromGoogleDriveM4B(m4bFileID: m4bFileID, folderID: folderID) {
                await MainActor.run {
                    appState.books.append(book)
                    
                    // If cover was found during import, update the book before saving
                    if let coverURL = book.coverImageURL {
                        if let index = appState.books.firstIndex(where: { $0.id == book.id }) {
                            appState.books[index].coverImageURL = coverURL
                        }
                    }
                    
                    PersistenceManager.shared.saveBooks(appState.books)
                    isImporting = false
                    dismiss()
                }
                
                // Transcription will happen automatically when user enters a chapter
            } else {
                await MainActor.run {
                    isImporting = false
                    // Could show an error alert here
                }
            }
        }
    }
}


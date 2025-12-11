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
                        BookRow(book: book)
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
        appState.currentBook = book
        // Update position from persistence
        let savedPosition = PersistenceManager.shared.loadPosition(for: book.id)
        var updatedBook = book
        updatedBook.currentPosition = savedPosition
        appState.currentBook = updatedBook
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
            
            // Book Info
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
                
                HStack(spacing: 8) {
                    if book.isDownloaded {
                        Label("Downloaded", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Cloud", systemImage: "icloud")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Text(formatDuration(book.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Progress Indicator
            if book.currentPosition > 0 {
                VStack {
                    ProgressView(value: book.currentPosition, total: max(book.duration, 1))
                        .frame(width: 40)
                    
                    Text(formatTime(book.currentPosition))
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
            if var book = await BookFileManager.shared.importBook(from: url) {
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
            if var book = await BookFileManager.shared.importBookFromGoogleDriveM4B(m4bFileID: m4bFileID, folderID: folderID) {
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
            } else {
                await MainActor.run {
                    isImporting = false
                    // Could show an error alert here
                }
            }
        }
    }
}


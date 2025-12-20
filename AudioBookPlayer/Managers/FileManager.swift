import Foundation
import AVFoundation
import Speech

class BookFileManager {
    static let shared = BookFileManager()
    
    private let documentsDirectory: URL
    
    private init() {
        let fileManager = FileManager.default
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // Create books directory if it doesn't exist
        let booksDirectory = documentsDirectory.appendingPathComponent("Books")
        if !fileManager.fileExists(atPath: booksDirectory.path) {
            try? fileManager.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Load Duration
    private func loadDuration(from asset: AVAsset) async -> TimeInterval {
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            if durationSeconds.isFinite && durationSeconds > 0 {
                return durationSeconds
            }
        } catch {
            print("Failed to load duration: \(error)")
        }
        return 0
    }
    
    // MARK: - Import Book
    func importBook(from sourceURL: URL) async -> Book? {
        let fileManager = FileManager.default
        
        // Get file name
        let fileName = sourceURL.lastPathComponent
        
        // Check if it's an M4B file
        guard fileName.lowercased().hasSuffix(".m4b") else {
            print("File is not an M4B file: \(fileName)")
            return nil
        }
        
        // Create destination URL in app's documents directory
        let booksDirectory = documentsDirectory.appendingPathComponent("Books")
        let destinationURL = booksDirectory.appendingPathComponent(fileName)
        
        // Copy file to app's documents directory
        do {
            // Remove existing file if it exists
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            // Copy the file
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            
            // Get book metadata
            let asset = AVAsset(url: destinationURL)
            
            // Extract title from filename (remove extension)
            let title = (fileName as NSString).deletingPathExtension
            
            // Load duration asynchronously
            let duration = await loadDuration(from: asset)
            
            // Create Book object with deterministic ID based on file path
            let bookID = DeterministicUUID.forBook(filePath: destinationURL.path)
            var book = Book(
                id: bookID,
                title: title,
                fileURL: destinationURL,
                duration: duration,
                isDownloaded: true
            )
            
            // Search and download cover image if not present
            if book.coverImageURL == nil {
                if let coverURL = await CoverImageManager.shared.searchAndDownloadCover(for: book) {
                    book.coverImageURL = coverURL
                }
            }
            
            return book
            
        } catch {
            print("Failed to import book: \(error)")
            return nil
        }
    }
    
    // MARK: - Import from Google Drive
    
    /// Import a book from Google Drive folder with all associated files
    func importBookFromGoogleDrive(folderID: String) async -> Book? {
        let fileManager = FileManager.default
        let booksDirectory = documentsDirectory.appendingPathComponent("Books")
        
        // Create a subdirectory for this book (using folder ID as identifier)
        let bookDirectory = booksDirectory.appendingPathComponent(folderID)
        
        do {
            // Create book directory if it doesn't exist
            if !fileManager.fileExists(atPath: bookDirectory.path) {
                try fileManager.createDirectory(at: bookDirectory, withIntermediateDirectories: true)
            }
            
            // Download all files from Google Drive
            let downloadedFiles = try await GoogleDriveManager.shared.downloadBookFolder(
                folderID: folderID,
                to: bookDirectory
            )
            
            // Ensure we have the M4B file
            guard let m4bFile = downloadedFiles.m4bFile else {
                return nil
            }
            
            // Get book metadata
            let asset = AVAsset(url: m4bFile)
            
            // Extract title from filename (remove extension)
            let fileName = m4bFile.lastPathComponent
            let title = (fileName as NSString).deletingPathExtension
            
            // Load duration asynchronously
            let duration = await loadDuration(from: asset)
            
            // Create Book object with deterministic ID based on file path
            let bookID = DeterministicUUID.forBook(filePath: m4bFile.path)
            var book = Book(
                id: bookID,
                title: title,
                fileURL: m4bFile,
                coverImageURL: downloadedFiles.coverImage,
                duration: duration,
                isDownloaded: true,
                googleDriveFileID: folderID
            )
            
            // Add associated files
            var associatedFiles: [URL] = []
            if let cueFile = downloadedFiles.cueFile {
                associatedFiles.append(cueFile)
            }
            if let nfoFile = downloadedFiles.nfoFile {
                associatedFiles.append(nfoFile)
            }
            book.associatedFiles = associatedFiles
            
            // Search and download cover image if not present
            if book.coverImageURL == nil {
                if let coverURL = await CoverImageManager.shared.searchAndDownloadCover(for: book) {
                    book.coverImageURL = coverURL
                }
            }
            
            return book
            
        } catch {
            return nil
        }
    }
    
    /// Import a book from Google Drive by M4B file ID
    func importBookFromGoogleDriveM4B(m4bFileID: String, folderID: String) async -> Book? {
        let fileManager = FileManager.default
        let booksDirectory = documentsDirectory.appendingPathComponent("Books")
        
        // Create a subdirectory for this book (using folder ID as identifier)
        let bookDirectory = booksDirectory.appendingPathComponent(folderID)
        
        do {
            // Create book directory if it doesn't exist
            if !fileManager.fileExists(atPath: bookDirectory.path) {
                try fileManager.createDirectory(at: bookDirectory, withIntermediateDirectories: true)
            }
            
            // Download M4B file and related files from Google Drive
            let downloadedFiles = try await GoogleDriveManager.shared.downloadBookByM4BFile(
                m4bFileID: m4bFileID,
                folderID: folderID,
                to: bookDirectory
            )
            
            // Ensure we have the M4B file
            guard let m4bFile = downloadedFiles.m4bFile else {
                print("No M4B file found in downloaded files")
                return nil
            }
            
            // Get book metadata
            let asset = AVAsset(url: m4bFile)
            
            // Extract title from filename (remove extension)
            let fileName = m4bFile.lastPathComponent
            let title = (fileName as NSString).deletingPathExtension
            
            // Load duration asynchronously
            let duration = await loadDuration(from: asset)
            
            // Create Book object with deterministic ID based on file path
            let bookID = DeterministicUUID.forBook(filePath: m4bFile.path)
            var book = Book(
                id: bookID,
                title: title,
                fileURL: m4bFile,
                coverImageURL: downloadedFiles.coverImage,
                duration: duration,
                isDownloaded: true,
                googleDriveFileID: folderID
            )
            
            // Add associated files
            var associatedFiles: [URL] = []
            if let cueFile = downloadedFiles.cueFile {
                associatedFiles.append(cueFile)
            }
            if let nfoFile = downloadedFiles.nfoFile {
                associatedFiles.append(nfoFile)
            }
            book.associatedFiles = associatedFiles
            
            // Search and download cover image if not present
            if book.coverImageURL == nil {
                if let coverURL = await CoverImageManager.shared.searchAndDownloadCover(for: book) {
                    book.coverImageURL = coverURL
                }
            }
            
            return book
            
        } catch {
            return nil
        }
    }
    
    // MARK: - Get Books Directory
    func getBooksDirectory() -> URL {
        return documentsDirectory.appendingPathComponent("Books")
    }
    
    // MARK: - Post-Import Transcription
    
    /// Queue first chapter transcription for a newly imported book
    /// This runs in the background after import to ensure first chapter is ready when user opens the book
    @available(iOS 26.0, *)
    func queueFirstChapterTranscription(for book: Book) async {
        // Check if transcription is enabled
        guard TranscriptionSettings.shared.isEnabled else {
            let disabledMsg = "🚫 [BookFileManager] Transcription is disabled - skipping first chapter transcription for book: '\(book.title)'"
            print(disabledMsg)
            FileLogger.shared.log(disabledMsg, category: "BookFileManager")
            return
        }
        
        // Check if SpeechTranscriber is available
        guard await TranscriptionManager.shared.isTranscriberAvailable() else {
            let unavailableMsg = "🚫 [BookFileManager] SpeechTranscriber is not available - skipping first chapter transcription for book: '\(book.title)'"
            print(unavailableMsg)
            FileLogger.shared.log(unavailableMsg, category: "BookFileManager")
            return
        }
        
        // Parse chapters from the book file
        let asset = AVAsset(url: book.fileURL)
        let duration = await loadDuration(from: asset)
        
        guard duration > 0 else {
            let invalidDurationMsg = "⚠️ [BookFileManager] Invalid duration for book '\(book.title)' - skipping first chapter transcription"
            print(invalidDurationMsg)
            FileLogger.shared.log(invalidDurationMsg, category: "BookFileManager")
            return
        }
        
        let chapters = ChapterParser.shared.parseChapters(from: asset, duration: duration, bookID: book.id)
        
        guard let firstChapter = chapters.first else {
            let noChaptersMsg = "⚠️ [BookFileManager] No chapters found for book '\(book.title)' - skipping first chapter transcription"
            print(noChaptersMsg)
            FileLogger.shared.log(noChaptersMsg, category: "BookFileManager")
            return
        }
        
        // First chapter is always at index 0
        let firstChapterIndex = 0
        
        // Check if first chapter is already transcribed
        let isTranscribed = await TranscriptionDatabase.shared.isChapterTranscribed(
            bookID: book.id,
            chapterIndex: firstChapterIndex
        )
        
        if isTranscribed {
            let alreadyDoneMsg = "✅ [BookFileManager] First chapter already transcribed for book '\(book.title)' - skipping"
            print(alreadyDoneMsg)
            FileLogger.shared.log(alreadyDoneMsg, category: "BookFileManager")
            return
        }
        
        // Check if already queued or running
        let isQueued = await TranscriptionQueue.shared.isChapterQueuedOrRunning(
            bookID: book.id,
            chapterIndex: firstChapterIndex
        )
        
        if isQueued {
            let alreadyQueuedMsg = "⚠️ [BookFileManager] First chapter already queued/running for book '\(book.title)' - skipping"
            print(alreadyQueuedMsg)
            FileLogger.shared.log(alreadyQueuedMsg, category: "BookFileManager")
            return
        }
        
        // Queue first chapter with low priority (so user-initiated transcriptions take precedence)
        let queueMsg = "📋 [BookFileManager] Queueing first chapter transcription for newly imported book: '\(book.title)', chapter='\(firstChapter.title)', chapterIndex=\(firstChapterIndex)"
        print(queueMsg)
        FileLogger.shared.log(queueMsg, category: "BookFileManager")
        
        await TranscriptionQueue.shared.enqueueChapter(
            book: book,
            chapterIndex: firstChapterIndex,
            startTime: firstChapter.startTime,
            endTime: firstChapter.endTime,
            priority: .low // Low priority so it doesn't block user-initiated transcriptions
        )
    }
}


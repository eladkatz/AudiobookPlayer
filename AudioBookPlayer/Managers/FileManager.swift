import Foundation
import AVFoundation

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
            
            // Create Book object
            let book = Book(
                title: title,
                fileURL: destinationURL,
                duration: duration,
                isDownloaded: true
            )
            
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
            
            // Create Book object with all associated files
            var book = Book(
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
            
            return book
            
        } catch {
            print("Failed to import book from Google Drive: \(error)")
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
            
            // Create Book object with all associated files
            var book = Book(
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
            
            return book
            
        } catch {
            print("Failed to import book from Google Drive: \(error)")
            return nil
        }
    }
    
    // MARK: - Get Books Directory
    func getBooksDirectory() -> URL {
        return documentsDirectory.appendingPathComponent("Books")
    }
}


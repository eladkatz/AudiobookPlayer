import Foundation
import UIKit

/// Manages automatic cover image search and download from Google Books API
class CoverImageManager: ObservableObject {
    static let shared = CoverImageManager()
    
    @Published var isSearching = false
    @Published var searchingBookID: UUID?
    
    private let baseURL = "https://www.googleapis.com/books/v1/volumes"
    let coversDirectory: URL
    
    private init() {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        coversDirectory = documentsDirectory.appendingPathComponent("Covers")
        
        // Create Covers directory if it doesn't exist
        if !fileManager.fileExists(atPath: coversDirectory.path) {
            try? fileManager.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Search and Download Cover
    
    /// Searches Google Books API and downloads cover image for a book
    /// - Parameter book: The book to find a cover for
    /// - Returns: URL of downloaded cover image, or nil if not found/failed
    func searchAndDownloadCover(for book: Book) async -> URL? {
        // Skip if book already has a cover
        if let existingCover = book.coverImageURL,
           FileManager.default.fileExists(atPath: existingCover.path) {
            return existingCover
        }
        
        // Check if cover already exists in Covers directory
        let coverURL = coversDirectory.appendingPathComponent("\(book.id.uuidString).jpg")
        if FileManager.default.fileExists(atPath: coverURL.path) {
            return coverURL
        }
        
        // Update searching state
        await MainActor.run {
            self.isSearching = true
            self.searchingBookID = book.id
        }
        
        defer {
            Task { @MainActor in
                if self.searchingBookID == book.id {
                    self.isSearching = false
                    self.searchingBookID = nil
                }
            }
        }
        
        // Build search query - clean up title (remove brackets, etc.)
        var cleanTitle = book.title
        // Remove common patterns like [ASIN] or [ISBN] from title
        cleanTitle = cleanTitle.replacingOccurrences(of: #"\[.*?\]"#, with: "", options: .regularExpression)
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespaces)
        
        var query = cleanTitle
        if let author = book.author {
            query += " inauthor:\(author)"
        }
        
        // URL encode the query properly
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "\(baseURL)?q=\(encodedQuery)&maxResults=1") else {
            print("⚠️ CoverImageManager: Failed to encode query or create URL: \(query)")
            return nil
        }
        
        do {
            // Search Google Books API
            let (data, response) = try await URLSession.shared.data(from: searchURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("⚠️ CoverImageManager: HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            
            // Parse JSON response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let firstItem = items.first,
                  let volumeInfo = firstItem["volumeInfo"] as? [String: Any],
                  let imageLinks = volumeInfo["imageLinks"] as? [String: Any] else {
                print("⚠️ CoverImageManager: No cover image found for '\(book.title)'")
                return nil
            }
            
            // Get the best available image URL (prefer thumbnail, fallback to smallThumbnail)
            guard let imageURLString = imageLinks["thumbnail"] as? String ?? imageLinks["smallThumbnail"] as? String else {
                print("⚠️ CoverImageManager: No image URL in response")
                return nil
            }
            
            // Convert HTTP to HTTPS for App Transport Security compliance
            var secureImageURLString = imageURLString.replacingOccurrences(of: "http://", with: "https://")
            
            // Also handle cases where the URL might have http: in the middle
            secureImageURLString = secureImageURLString.replacingOccurrences(of: "http:", with: "https:")
            
            guard let imageURL = URL(string: secureImageURLString) else {
                print("⚠️ CoverImageManager: Invalid image URL: \(secureImageURLString)")
                return nil
            }
            
            print("🔍 CoverImageManager: Downloading cover from: \(secureImageURLString)")
            
            // Download the image
            let downloadedURL = try await downloadImage(from: imageURL, to: coverURL)
            
            print("✅ CoverImageManager: Downloaded cover for '\(book.title)'")
            return downloadedURL
            
        } catch {
            print("⚠️ CoverImageManager: Error searching/downloading cover: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                print("⚠️ CoverImageManager: URL Error - \(urlError.localizedDescription), code: \(urlError.code.rawValue)")
            }
            return nil
        }
    }
    
    // MARK: - Download Image
    
    /// Downloads an image from a URL and saves it to disk
    /// - Parameters:
    ///   - url: Source image URL
    ///   - destination: Local file URL to save to
    /// - Returns: Destination URL if successful
    private func downloadImage(from url: URL, to destination: URL) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "CoverImageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "HTTP error"])
        }
        
        // Verify it's an image
        guard let image = UIImage(data: data) else {
            throw NSError(domain: "CoverImageManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }
        
        // Convert to JPEG and save
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "CoverImageManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to convert to JPEG"])
        }
        
        try jpegData.write(to: destination)
        return destination
    }
    
    // MARK: - Retry Failed Downloads
    
    /// Retries cover downloads for books that don't have covers
    /// Call this on app launch to retry failed downloads
    /// - Returns: Dictionary mapping book IDs to cover URLs for successfully downloaded covers
    func retryFailedDownloads(for books: [Book]) async -> [UUID: URL] {
        let booksWithoutCovers = books.filter { book in
            guard let coverURL = book.coverImageURL else {
                return true
            }
            // Check if cover file exists
            return !FileManager.default.fileExists(atPath: coverURL.path)
        }
        
        print("🔄 CoverImageManager: Retrying cover downloads for \(booksWithoutCovers.count) books")
        
        var downloadedCovers: [UUID: URL] = [:]
        
        for book in booksWithoutCovers {
            // Small delay between requests to avoid rate limiting
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            if let coverURL = await searchAndDownloadCover(for: book) {
                downloadedCovers[book.id] = coverURL
                print("✅ CoverImageManager: Successfully downloaded cover for '\(book.title)'")
            }
        }
        
        return downloadedCovers
    }
}


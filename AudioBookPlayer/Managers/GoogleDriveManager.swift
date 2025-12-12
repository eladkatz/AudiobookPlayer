import Foundation
import UIKit
import GoogleSignIn

/// Manages Google Drive authentication and file operations
class GoogleDriveManager: NSObject, ObservableObject {
    static let shared = GoogleDriveManager()
    
    // Client ID from Google Cloud Console
    private let clientID = "705211842020-0epij93sncs4uc5ogran3it8mqj7g416.apps.googleusercontent.com"
    
    @Published var isAuthenticated = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var currentDownloadFile: String = ""
    
    private var currentUser: GIDGoogleUser?
    
    private override init() {
        super.init()
        setupGoogleSignIn()
        checkAuthenticationStatus()
    }
    
    // MARK: - Authentication
    
    /// Set up Google Sign-In configuration
    private func setupGoogleSignIn() {
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
    }
    
    /// Check if user is already authenticated and restore session if possible
    func checkAuthenticationStatus() {
        setupGoogleSignIn()
        
        // First, try to restore previous sign-in from keychain (important for physical devices)
        Task { @MainActor in
            do {
                // Restore previous sign-in session from keychain
                let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                
                // Check if the user has the required scopes
                let requiredScope = "https://www.googleapis.com/auth/drive.readonly"
                if let grantedScopes = user.grantedScopes,
                   grantedScopes.contains(requiredScope) {
                    self.currentUser = user
                    self.isAuthenticated = true
                    print("✅ GoogleDrive: Restored authentication from previous session")
                } else {
                    // User exists but doesn't have the required scope, need to re-authenticate
                    print("🔍 GoogleDrive: User found but missing required scope, will need to sign in again")
                    self.currentUser = nil
                    self.isAuthenticated = false
                }
            } catch {
                // No previous sign-in found or restore failed
                // Check if there's a current user as fallback
                if let user = GIDSignIn.sharedInstance.currentUser {
                    let requiredScope = "https://www.googleapis.com/auth/drive.readonly"
                    if let grantedScopes = user.grantedScopes,
                       grantedScopes.contains(requiredScope) {
                        self.currentUser = user
                        self.isAuthenticated = true
                        print("✅ GoogleDrive: Restored authentication from current user")
                    } else {
                        self.currentUser = nil
                        self.isAuthenticated = false
                        print("🔍 GoogleDrive: Current user found but missing required scope")
                    }
                } else {
                    self.currentUser = nil
                    self.isAuthenticated = false
                    print("🔍 GoogleDrive: No existing authentication found")
                }
            }
        }
    }
    
    /// Sign in with Google
    @MainActor
    func signIn(presentingViewController: UIViewController) async throws {
        setupGoogleSignIn()
        
        // Request Drive API scope
        let additionalScopes = ["https://www.googleapis.com/auth/drive.readonly"]
        
        print("🔍 GoogleDrive: Starting sign-in with scopes: \(additionalScopes)")
        
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: nil,
            additionalScopes: additionalScopes
        )
        self.currentUser = result.user
        self.isAuthenticated = true
        
        print("✅ GoogleDrive: Signed in successfully")
        if let grantedScopes = result.user.grantedScopes {
            print("✅ GoogleDrive: Granted scopes: \(grantedScopes)")
        }
    }
    
    /// Sign out
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        self.currentUser = nil
        self.isAuthenticated = false
    }
    
    // MARK: - File Operations
    
    /// List files in a Google Drive folder
    func listFiles(in folderID: String) async throws -> [GoogleDriveFile] {
        guard let user = currentUser else {
            throw GoogleDriveError.notAuthenticated
        }
        
        // Get access token (will be refreshed automatically if needed)
        let accessToken = user.accessToken.tokenString
        let encodedFolderID = folderID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? folderID
        let urlString = "https://www.googleapis.com/drive/v3/files?q='\(encodedFolderID)'+in+parents+and+trashed=false&fields=files(id,name,mimeType,size,shortcutDetails)"
        
        print("🔍 GoogleDrive: Listing files in folder: \(folderID)")
        print("🔍 GoogleDrive: URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ GoogleDrive: Invalid URL")
            throw GoogleDriveError.downloadFailed
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ GoogleDrive: Invalid HTTP response")
                throw GoogleDriveError.downloadFailed
            }
            
            print("🔍 GoogleDrive: HTTP Status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                // Try to decode error response
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorData["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ GoogleDrive API Error: \(message)")
                    print("❌ GoogleDrive Error Details: \(error)")
                } else if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ GoogleDrive Error Response: \(errorString)")
                }
                throw GoogleDriveError.apiError(statusCode: httpResponse.statusCode, message: "HTTP \(httpResponse.statusCode)")
            }
            
            let driveResponse = try JSONDecoder().decode(GoogleDriveFileListResponse.self, from: data)
            print("✅ GoogleDrive: Found \(driveResponse.files.count) files")
            
            return driveResponse.files
        } catch let error as GoogleDriveError {
            throw error
        } catch {
            print("❌ GoogleDrive: Unexpected error: \(error.localizedDescription)")
            throw GoogleDriveError.downloadFailed
        }
    }
    
    /// List folders shared with the user
    func listSharedFolders() async throws -> [GoogleDriveFile] {
        guard let user = currentUser else {
            throw GoogleDriveError.notAuthenticated
        }
        
        // Get access token (will be refreshed automatically if needed)
        let accessToken = user.accessToken.tokenString
        // Query for folders that are shared with the user
        let query = "sharedWithMe=true and trashed=false and mimeType='application/vnd.google-apps.folder'"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id,name,mimeType,size,shortcutDetails)"
        
        print("🔍 GoogleDrive: Listing shared folders")
        print("🔍 GoogleDrive: URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ GoogleDrive: Invalid URL")
            throw GoogleDriveError.downloadFailed
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ GoogleDrive: Invalid HTTP response")
                throw GoogleDriveError.downloadFailed
            }
            
            print("🔍 GoogleDrive: HTTP Status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                // Try to decode error response
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorData["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ GoogleDrive API Error: \(message)")
                    print("❌ GoogleDrive Error Details: \(error)")
                } else if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ GoogleDrive Error Response: \(errorString)")
                }
                throw GoogleDriveError.apiError(statusCode: httpResponse.statusCode, message: "HTTP \(httpResponse.statusCode)")
            }
            
            let driveResponse = try JSONDecoder().decode(GoogleDriveFileListResponse.self, from: data)
            print("✅ GoogleDrive: Found \(driveResponse.files.count) shared folders")
            
            return driveResponse.files
        } catch let error as GoogleDriveError {
            throw error
        } catch {
            print("❌ GoogleDrive: Unexpected error: \(error.localizedDescription)")
            throw GoogleDriveError.downloadFailed
        }
    }
    
    /// Download a file from Google Drive
    func downloadFile(fileID: String, fileName: String, to destinationURL: URL) async throws {
        guard let user = currentUser else {
            throw GoogleDriveError.notAuthenticated
        }
        
        let accessToken = user.accessToken.tokenString
        let urlString = "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media"
        
        guard let url = URL(string: urlString) else {
            throw GoogleDriveError.downloadFailed
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // Reset progress at start of each file
        await MainActor.run {
            self.downloadProgress = 0.0
        }
        
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GoogleDriveError.downloadFailed
        }
        
        // Create directory if needed
        let directory = destinationURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        
        // Create empty file first
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        
        guard let fileHandle = try? FileHandle(forWritingTo: destinationURL) else {
            throw GoogleDriveError.downloadFailed
        }
        defer { try? fileHandle.close() }
        
        let totalBytes = httpResponse.expectedContentLength
        var buffer = Data()
        let bufferSize = 8192 // 8KB buffer
        var bytesWritten: Int64 = 0
        var lastProgressUpdate: Double = -1.0
        let progressUpdateThreshold = 0.01 // Update every 1% change
        
        for try await byte in asyncBytes {
            buffer.append(byte)
            bytesWritten += 1
            
            // Write in chunks for better performance
            if buffer.count >= bufferSize {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll()
                
                // Update progress periodically, but throttle updates to avoid jitter
                if totalBytes > 0 {
                    let progress = Double(bytesWritten) / Double(totalBytes)
                    // Only update if progress changed by at least 1%
                    if abs(progress - lastProgressUpdate) >= progressUpdateThreshold || progress >= 1.0 {
                        await MainActor.run {
                            self.downloadProgress = min(progress, 1.0)
                        }
                        lastProgressUpdate = progress
                    }
                }
            }
        }
        
        // Write remaining buffer
        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
        }
        
        // Final progress update
        await MainActor.run {
            self.downloadProgress = 1.0
        }
    }
    
    /// Download all files for a book from a Google Drive folder
    func downloadBookFolder(folderID: String, to destinationDirectory: URL) async throws -> BookFiles {
        await MainActor.run {
            self.isDownloading = true
            self.downloadProgress = 0.0
        }
        
        defer {
            Task { @MainActor in
                self.isDownloading = false
                self.downloadProgress = 0.0
            }
        }
        
        let files = try await listFiles(in: folderID)
        
        // Find M4B file
        guard let m4bFile = files.first(where: { $0.name.lowercased().hasSuffix(".m4b") }) else {
            throw GoogleDriveError.noM4BFileFound
        }
        
        let baseName = (m4bFile.name as NSString).deletingPathExtension
        
        // Find associated files
        let cueFile = files.first { file in
            let name = file.name.lowercased()
            return name == "\(baseName.lowercased()).cue" || 
                   name == "\(baseName.lowercased()).m4b.cue"
        }
        
        let imageFile = files.first { file in
            let name = file.name.lowercased()
            let ext = (name as NSString).pathExtension
            return (ext == "jpg" || ext == "jpeg") && (
                name == "\(baseName.lowercased()).jpg" ||
                name == "\(baseName.lowercased()).jpeg" ||
                name == "cover.jpg" ||
                name == "folder.jpg"
            )
        }
        
        let nfoFile = files.first { file in
            file.name.lowercased() == "\(baseName.lowercased()).nfo"
        }
        
        var downloadedFiles = BookFiles()
        
        // Download M4B file
        await MainActor.run {
            self.currentDownloadFile = m4bFile.name
        }
        let m4bDestination = destinationDirectory.appendingPathComponent(m4bFile.name)
        try await downloadFile(fileID: m4bFile.id, fileName: m4bFile.name, to: m4bDestination)
        downloadedFiles.m4bFile = m4bDestination
        
        // Download CUE file if found
        if let cueFile = cueFile {
            await MainActor.run {
                self.currentDownloadFile = cueFile.name
            }
            let cueDestination = destinationDirectory.appendingPathComponent(cueFile.name)
            try await downloadFile(fileID: cueFile.id, fileName: cueFile.name, to: cueDestination)
            downloadedFiles.cueFile = cueDestination
        }
        
        // Download image file if found
        if let imageFile = imageFile {
            await MainActor.run {
                self.currentDownloadFile = imageFile.name
            }
            let imageDestination = destinationDirectory.appendingPathComponent(imageFile.name)
            try await downloadFile(fileID: imageFile.id, fileName: imageFile.name, to: imageDestination)
            downloadedFiles.coverImage = imageDestination
        }
        
        // Download NFO file if found (for future use)
        if let nfoFile = nfoFile {
            await MainActor.run {
                self.currentDownloadFile = nfoFile.name
            }
            let nfoDestination = destinationDirectory.appendingPathComponent(nfoFile.name)
            try await downloadFile(fileID: nfoFile.id, fileName: nfoFile.name, to: nfoDestination)
            downloadedFiles.nfoFile = nfoDestination
        }
        
        downloadedFiles.googleDriveFolderID = folderID
        
        return downloadedFiles
    }
    
    /// Download a book by M4B file ID, automatically finding related files in the same folder
    func downloadBookByM4BFile(m4bFileID: String, folderID: String, to destinationDirectory: URL) async throws -> BookFiles {
        await MainActor.run {
            self.isDownloading = true
            self.downloadProgress = 0.0
        }
        
        defer {
            Task { @MainActor in
                self.isDownloading = false
                self.downloadProgress = 0.0
            }
        }
        
        // List all files in the folder
        let files = try await listFiles(in: folderID)
        
        // Find the M4B file
        guard let m4bFile = files.first(where: { $0.id == m4bFileID && $0.name.lowercased().hasSuffix(".m4b") }) else {
            throw GoogleDriveError.noM4BFileFound
        }
        
        let baseName = (m4bFile.name as NSString).deletingPathExtension
        
        // Find associated files in the same folder
        let cueFile = files.first { file in
            let name = file.name.lowercased()
            return name == "\(baseName.lowercased()).cue" || 
                   name == "\(baseName.lowercased()).m4b.cue"
        }
        
        let imageFile = files.first { file in
            let name = file.name.lowercased()
            let ext = (name as NSString).pathExtension
            return (ext == "jpg" || ext == "jpeg") && (
                name == "\(baseName.lowercased()).jpg" ||
                name == "\(baseName.lowercased()).jpeg" ||
                name == "cover.jpg" ||
                name == "folder.jpg"
            )
        }
        
        let nfoFile = files.first { file in
            file.name.lowercased() == "\(baseName.lowercased()).nfo"
        }
        
        var downloadedFiles = BookFiles()
        
        // Download M4B file
        await MainActor.run {
            self.currentDownloadFile = m4bFile.name
        }
        let m4bDestination = destinationDirectory.appendingPathComponent(m4bFile.name)
        try await downloadFile(fileID: m4bFile.id, fileName: m4bFile.name, to: m4bDestination)
        downloadedFiles.m4bFile = m4bDestination
        
        // Download CUE file if found
        if let cueFile = cueFile {
            await MainActor.run {
                self.currentDownloadFile = cueFile.name
            }
            let cueDestination = destinationDirectory.appendingPathComponent(cueFile.name)
            try await downloadFile(fileID: cueFile.id, fileName: cueFile.name, to: cueDestination)
            downloadedFiles.cueFile = cueDestination
        }
        
        // Download image file if found
        if let imageFile = imageFile {
            await MainActor.run {
                self.currentDownloadFile = imageFile.name
            }
            let imageDestination = destinationDirectory.appendingPathComponent(imageFile.name)
            try await downloadFile(fileID: imageFile.id, fileName: imageFile.name, to: imageDestination)
            downloadedFiles.coverImage = imageDestination
        }
        
        // Download NFO file if found (for future use)
        if let nfoFile = nfoFile {
            await MainActor.run {
                self.currentDownloadFile = nfoFile.name
            }
            let nfoDestination = destinationDirectory.appendingPathComponent(nfoFile.name)
            try await downloadFile(fileID: nfoFile.id, fileName: nfoFile.name, to: nfoDestination)
            downloadedFiles.nfoFile = nfoDestination
        }
        
        downloadedFiles.googleDriveFolderID = folderID
        
        return downloadedFiles
    }
    
    /// Resolve a shortcut to its target file/folder
    func resolveShortcut(shortcutID: String) async throws -> GoogleDriveFile {
        guard let user = currentUser else {
            throw GoogleDriveError.notAuthenticated
        }
        
        let accessToken = user.accessToken.tokenString
        let urlString = "https://www.googleapis.com/drive/v3/files/\(shortcutID)?fields=id,name,mimeType,size,shortcutDetails"
        
        guard let url = URL(string: urlString) else {
            throw GoogleDriveError.downloadFailed
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GoogleDriveError.downloadFailed
        }
        
        let shortcut = try JSONDecoder().decode(GoogleDriveFile.self, from: data)
        
        // Get the target file/folder info
        guard let targetID = shortcut.shortcutDetails?.targetId else {
            throw GoogleDriveError.downloadFailed
        }
        
        // Fetch the target file/folder
        let targetURLString = "https://www.googleapis.com/drive/v3/files/\(targetID)?fields=id,name,mimeType,size,shortcutDetails"
        
        guard let targetURL = URL(string: targetURLString) else {
            throw GoogleDriveError.downloadFailed
        }
        
        var targetRequest = URLRequest(url: targetURL)
        targetRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        targetRequest.httpMethod = "GET"
        
        let (targetData, targetResponse) = try await URLSession.shared.data(for: targetRequest)
        
        guard let targetHttpResponse = targetResponse as? HTTPURLResponse,
              targetHttpResponse.statusCode == 200 else {
            throw GoogleDriveError.downloadFailed
        }
        
        let target = try JSONDecoder().decode(GoogleDriveFile.self, from: targetData)
        return target
    }
    
    /// Search for files and folders by name
    func searchFiles(query: String) async throws -> [GoogleDriveFile] {
        guard let user = currentUser else {
            throw GoogleDriveError.notAuthenticated
        }
        
        let accessToken = user.accessToken.tokenString
        // Search for files/folders that match the query and are not trashed
        let searchQuery = "name contains '\(query)' and trashed=false"
        let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
        let urlString = "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id,name,mimeType,size,shortcutDetails)"
        
        print("🔍 GoogleDrive: Searching for: \(query)")
        print("🔍 GoogleDrive: URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ GoogleDrive: Invalid URL")
            throw GoogleDriveError.downloadFailed
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ GoogleDrive: Invalid HTTP response")
                throw GoogleDriveError.downloadFailed
            }
            
            print("🔍 GoogleDrive: HTTP Status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                // Try to decode error response
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorData["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ GoogleDrive API Error: \(message)")
                    print("❌ GoogleDrive Error Details: \(error)")
                } else if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ GoogleDrive Error Response: \(errorString)")
                }
                throw GoogleDriveError.apiError(statusCode: httpResponse.statusCode, message: "HTTP \(httpResponse.statusCode)")
            }
            
            let driveResponse = try JSONDecoder().decode(GoogleDriveFileListResponse.self, from: data)
            print("✅ GoogleDrive: Found \(driveResponse.files.count) search results")
            
            return driveResponse.files
        } catch let error as GoogleDriveError {
            throw error
        } catch {
            print("❌ GoogleDrive: Unexpected error: \(error.localizedDescription)")
            throw GoogleDriveError.downloadFailed
        }
    }
}

// MARK: - Models

struct GoogleDriveFile: Codable {
    let id: String
    let name: String
    let mimeType: String
    let size: String?
    let shortcutDetails: ShortcutDetails?
    
    struct ShortcutDetails: Codable {
        let targetId: String
        let targetMimeType: String
    }
}

struct GoogleDriveFileListResponse: Codable {
    let files: [GoogleDriveFile]
}

struct BookFiles {
    var m4bFile: URL?
    var cueFile: URL?
    var coverImage: URL?
    var nfoFile: URL?
    var googleDriveFolderID: String?
}

enum GoogleDriveError: LocalizedError {
    case notAuthenticated
    case authenticationFailed
    case invalidConfiguration
    case downloadFailed
    case noM4BFileFound
    case notImplemented
    case apiError(statusCode: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to Google Drive first"
        case .authenticationFailed:
            return "Failed to authenticate with Google Drive"
        case .invalidConfiguration:
            return "Invalid Google Drive configuration"
        case .downloadFailed:
            return "Failed to download file from Google Drive"
        case .noM4BFileFound:
            return "No M4B file found in the selected folder"
        case .notImplemented:
            return "Google Drive integration not yet implemented. Please add Google Sign-In SDK first."
        case .apiError(let statusCode, let message):
            return "Google Drive API error (\(statusCode)): \(message)"
        }
    }
}


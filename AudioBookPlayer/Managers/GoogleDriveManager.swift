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
                } else {
                    // User exists but doesn't have the required scope, need to re-authenticate
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
                    } else {
                        self.currentUser = nil
                        self.isAuthenticated = false
                    }
                } else {
                    self.currentUser = nil
                    self.isAuthenticated = false
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
        
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: nil,
            additionalScopes: additionalScopes
        )
        self.currentUser = result.user
        self.isAuthenticated = true
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
        
        // For shared files, we need to use 'sharedWithMe' or check permissions
        // Note: When listing files in a shared folder, we use the folder ID directly
        let urlString = "https://www.googleapis.com/drive/v3/files?q='\(encodedFolderID)'+in+parents+and+trashed=false&fields=files(id,name,mimeType,size,shortcutDetails,parents)"
        
        
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
        
        guard let url = URL(string: urlString) else {
            throw GoogleDriveError.downloadFailed
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleDriveError.downloadFailed
            }
            
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
        
        // Check available disk space before starting download
        let availableSpace = getAvailableDiskSpace()
        
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
        
        let (asyncBytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw GoogleDriveError.downloadFailed
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveError.downloadFailed
        }
        
        guard httpResponse.statusCode == 200 else {
            // Check for specific error codes
            switch httpResponse.statusCode {
            case 403:
                throw GoogleDriveError.apiError(statusCode: 403, message: "Access denied. This file may be shared and you may not have download permissions.")
            case 404:
                throw GoogleDriveError.apiError(statusCode: 404, message: "File not found. The file may have been moved or deleted.")
            case 507:
                throw GoogleDriveError.apiError(statusCode: 507, message: "Insufficient storage on Google Drive.")
            default:
                throw GoogleDriveError.apiError(statusCode: httpResponse.statusCode, message: "Download failed with HTTP \(httpResponse.statusCode)")
            }
        }
        
        let totalBytes = httpResponse.expectedContentLength
        
        // Check if we have enough space (with 10% buffer)
        if totalBytes > 0 && availableSpace > 0 {
            let requiredSpace = totalBytes + (totalBytes / 10) // 10% buffer
            if availableSpace < requiredSpace {
                let errorMsg = "Insufficient disk space. Required: \(formatBytes(requiredSpace)), Available: \(formatBytes(availableSpace))"
                throw GoogleDriveError.apiError(statusCode: 507, message: errorMsg)
            }
        }
        
        // Create directory if needed
        let directory = destinationURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw GoogleDriveError.downloadFailed
        }
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        
        // Create empty file first
        let fileCreated = FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        if !fileCreated {
            throw GoogleDriveError.downloadFailed
        }
        
        guard let fileHandle = try? FileHandle(forWritingTo: destinationURL) else {
            throw GoogleDriveError.downloadFailed
        }
        defer { 
            try? fileHandle.close()
        }
        
        var buffer = Data()
        let bufferSize = 8192 // 8KB buffer
        var bytesWritten: Int64 = 0
        var lastProgressUpdate: Double = -1.0
        let progressUpdateThreshold = 0.01 // Update every 1% change
        var lastSpaceCheck: Int64 = 0
        let spaceCheckInterval: Int64 = 10 * 1024 * 1024 // Check every 10MB
        
        do {
            for try await byte in asyncBytes {
                buffer.append(byte)
                bytesWritten += 1
                
                // Write in chunks for better performance
                if buffer.count >= bufferSize {
                    do {
                        try fileHandle.write(contentsOf: buffer)
                        buffer.removeAll()
                        
                        // Check disk space periodically during download
                        if bytesWritten - lastSpaceCheck > spaceCheckInterval {
                            let currentSpace = getAvailableDiskSpace()
                            if currentSpace < 10 * 1024 * 1024 { // Less than 10MB
                                print("⚠️ GoogleDrive: Low disk space warning: \(formatBytes(currentSpace))")
                            }
                            lastSpaceCheck = bytesWritten
                        }
                        
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
                    } catch {
                        if let nsError = error as NSError? {
                            if nsError.domain == NSPOSIXErrorDomain {
                                switch nsError.code {
                                case 28: // ENOSPC - No space left on device
                                    throw GoogleDriveError.apiError(statusCode: 507, message: "No space left on device. Please free up space and try again.")
                                default:
                                    break
                                }
                            }
                        }
                        throw GoogleDriveError.downloadFailed
                    }
                }
            }
        } catch {
            throw error
        }
        
        // Write remaining buffer
        if !buffer.isEmpty {
            do {
                try fileHandle.write(contentsOf: buffer)
            } catch {
                throw GoogleDriveError.downloadFailed
            }
        }
        
        // Verify file was written
        if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
           let fileSize = fileAttributes[.size] as? Int64 {
            if totalBytes > 0 && fileSize != totalBytes {
                print("⚠️ GoogleDrive: File size mismatch! Expected \(formatBytes(totalBytes)), got \(formatBytes(fileSize))")
            }
        }
        
        // Final progress update
        await MainActor.run {
            self.downloadProgress = 1.0
        }
    }
    
    /// Get available disk space in bytes
    private func getAvailableDiskSpace() -> Int64 {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return -1
        }
        
        do {
            let resourceValues = try documentsPath.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let availableCapacity = resourceValues.volumeAvailableCapacityForImportantUsage {
                return availableCapacity
            }
        } catch {
            print("⚠️ GoogleDrive: Could not get disk space: \(error)")
        }
        
        // Fallback: try system attributes
        if let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: documentsPath.path),
           let freeSize = systemAttributes[.systemFreeSize] as? Int64 {
            return freeSize
        }
        
        return -1
    }
    
    /// Format bytes to human-readable string
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
        let m4bFiles = files.filter { $0.name.lowercased().hasSuffix(".m4b") }
        
        guard let m4bFile = m4bFiles.first else {
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
            try? await downloadFile(fileID: cueFile.id, fileName: cueFile.name, to: cueDestination)
            downloadedFiles.cueFile = cueDestination
        }
        
        // Download image file if found
        if let imageFile = imageFile {
            await MainActor.run {
                self.currentDownloadFile = imageFile.name
            }
            let imageDestination = destinationDirectory.appendingPathComponent(imageFile.name)
            try? await downloadFile(fileID: imageFile.id, fileName: imageFile.name, to: imageDestination)
            downloadedFiles.coverImage = imageDestination
        }
        
        // Download NFO file if found (for future use)
        if let nfoFile = nfoFile {
            await MainActor.run {
                self.currentDownloadFile = nfoFile.name
            }
            let nfoDestination = destinationDirectory.appendingPathComponent(nfoFile.name)
            try? await downloadFile(fileID: nfoFile.id, fileName: nfoFile.name, to: nfoDestination)
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
        let matchingFiles = files.filter { $0.id == m4bFileID && $0.name.lowercased().hasSuffix(".m4b") }
        
        guard let m4bFile = matchingFiles.first else {
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
            try? await downloadFile(fileID: cueFile.id, fileName: cueFile.name, to: cueDestination)
            downloadedFiles.cueFile = cueDestination
        }
        
        // Download image file if found
        if let imageFile = imageFile {
            await MainActor.run {
                self.currentDownloadFile = imageFile.name
            }
            let imageDestination = destinationDirectory.appendingPathComponent(imageFile.name)
            try? await downloadFile(fileID: imageFile.id, fileName: imageFile.name, to: imageDestination)
            downloadedFiles.coverImage = imageDestination
        }
        
        // Download NFO file if found (for future use)
        if let nfoFile = nfoFile {
            await MainActor.run {
                self.currentDownloadFile = nfoFile.name
            }
            let nfoDestination = destinationDirectory.appendingPathComponent(nfoFile.name)
            try? await downloadFile(fileID: nfoFile.id, fileName: nfoFile.name, to: nfoDestination)
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
        
        guard let targetHttpResponse = targetResponse as? HTTPURLResponse else {
            throw GoogleDriveError.downloadFailed
        }
        
        guard targetHttpResponse.statusCode == 200 else {
            throw GoogleDriveError.downloadFailed
        }
        
        let target = try JSONDecoder().decode(GoogleDriveFile.self, from: targetData)
        return target
    }
    
    /// Get file metadata including parent folder information
    func getFileMetadata(fileID: String) async throws -> GoogleDriveFile {
        guard let user = currentUser else {
            throw GoogleDriveError.notAuthenticated
        }
        
        let accessToken = user.accessToken.tokenString
        let urlString = "https://www.googleapis.com/drive/v3/files/\(fileID)?fields=id,name,mimeType,size,shortcutDetails,parents"
        
        guard let url = URL(string: urlString) else {
            throw GoogleDriveError.downloadFailed
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleDriveError.downloadFailed
            }
            
            guard httpResponse.statusCode == 200 else {
                throw GoogleDriveError.apiError(statusCode: httpResponse.statusCode, message: "Failed to get file metadata")
            }
            
            let file = try JSONDecoder().decode(GoogleDriveFile.self, from: data)
            return file
        } catch let error as GoogleDriveError {
            throw error
        } catch {
            throw GoogleDriveError.downloadFailed
        }
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
        let urlString = "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id,name,mimeType,size,shortcutDetails,parents)"
        
        guard let url = URL(string: urlString) else {
            throw GoogleDriveError.downloadFailed
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleDriveError.downloadFailed
            }
            
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
    let parents: [String]?
    
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
            return "Please sign in to Google Drive first to import books."
        case .authenticationFailed:
            return "Failed to sign in to Google Drive. Please try again."
        case .invalidConfiguration:
            return "Google Drive is not properly configured. Please contact support."
        case .downloadFailed:
            return "Failed to download the book from Google Drive. Please check your internet connection and try again."
        case .noM4BFileFound:
            return "No audiobook file (.m4b) found in the selected location. Please make sure you're selecting a folder or file that contains an M4B audiobook file."
        case .notImplemented:
            return "Google Drive integration is not available. Please contact support."
        case .apiError(let statusCode, let message):
            switch statusCode {
            case 403:
                return "Access denied. You may not have permission to access this file, or it may be in a shared folder that requires different access. Try navigating to the file's folder instead of using search."
            case 404:
                return "File not found. The file may have been moved, deleted, or you may not have access to it."
            case 507:
                return "Insufficient storage. Please free up space on your device and try again."
            case 401:
                return "Authentication expired. Please sign out and sign back in to Google Drive."
            default:
                if !message.isEmpty && message != "HTTP \(statusCode)" {
                    return "Google Drive error: \(message)"
                }
                return "Google Drive error (code \(statusCode)). Please try again or contact support if the problem persists."
            }
        }
    }
}


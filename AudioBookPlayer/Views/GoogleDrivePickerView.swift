import SwiftUI
import GoogleSignIn

struct GoogleDrivePickerView: View {
    @ObservedObject var driveManager = GoogleDriveManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var navigationStack: [(id: String, name: String)] = [("root", "My Drive")]
    @State private var folderContents: [GoogleDriveFile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var onM4BSelected: ((String, String) -> Void)? // (m4bFileID, folderID)
    
    private var currentFolderID: String {
        navigationStack.last?.id ?? "root"
    }
    
    private var currentFolderName: String {
        navigationStack.last?.name ?? "My Drive"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if !driveManager.isAuthenticated {
                    authenticationView
                } else if isLoading {
                    ProgressView("Loading...")
                } else {
                    folderContentsView
                }
            }
            .navigationTitle(currentFolderName)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if navigationStack.count > 1 {
                        Button("Back") {
                            navigationStack.removeLast()
                            Task {
                                await loadFolderContents(folderID: currentFolderID, folderName: currentFolderName)
                            }
                        }
                    } else {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
                
                if driveManager.isAuthenticated {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Sign Out") {
                            driveManager.signOut()
                        }
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                // Re-check authentication status in case it was restored
                driveManager.checkAuthenticationStatus()
                if driveManager.isAuthenticated {
                    Task {
                        await loadFolderContents(folderID: currentFolderID, folderName: currentFolderName)
                    }
                }
            }
            .onChange(of: driveManager.isAuthenticated) { oldValue, newValue in
                // When authentication state changes to true, load folder contents
                if newValue && !oldValue {
                    Task {
                        await loadFolderContents(folderID: currentFolderID, folderName: currentFolderName)
                    }
                }
            }
        }
    }
    
    // MARK: - Authentication View
    
    private var authenticationView: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Sign in to Google Drive")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Sign in to access your audiobooks stored in Google Drive")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                signIn()
            }) {
                HStack {
                    Image(systemName: "person.circle.fill")
                    Text("Sign in with Google")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    // MARK: - Folder Contents View
    
    private var folderContentsView: some View {
        List {
            if folderContents.isEmpty {
                Text("No files or folders found")
                    .foregroundColor(.secondary)
            } else {
                // Folders section
                let folders = folderContents.filter { $0.mimeType == "application/vnd.google-apps.folder" }
                if !folders.isEmpty {
                    Section("Folders") {
                        ForEach(folders, id: \.id) { folder in
                            Button(action: {
                                navigateToFolder(folderID: folder.id, folderName: folder.name)
                            }) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.blue)
                                    Text(folder.name)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
                
                // Files section
                let files = folderContents.filter { $0.mimeType != "application/vnd.google-apps.folder" }
                if !files.isEmpty {
                    Section("Files") {
                        ForEach(files, id: \.id) { file in
                            fileRow(for: file)
                        }
                    }
                }
            }
        }
        .refreshable {
            await loadFolderContents(folderID: currentFolderID, folderName: currentFolderName)
        }
    }
    
    // MARK: - File Row
    
    private func fileRow(for file: GoogleDriveFile) -> some View {
        let isM4B = file.name.lowercased().hasSuffix(".m4b")
        
        return HStack {
            Image(systemName: iconName(for: file))
                .foregroundColor(isM4B ? .blue : .secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(isM4B ? .headline : .body)
                    .foregroundColor(isM4B ? .primary : .secondary)
                
                if let size = file.size, let sizeBytes = Int64(size) {
                    Text(formatFileSize(sizeBytes))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isM4B {
                Button(action: {
                    selectM4BFile(fileID: file.id, folderID: currentFolderID)
                }) {
                    Text("Import")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Helper Methods
    
    private func signIn() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Could not find view controller"
            return
        }
        
        Task { @MainActor in
            do {
                try await driveManager.signIn(presentingViewController: rootViewController)
                await loadFolderContents(folderID: "root", folderName: "My Drive")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func loadFolderContents(folderID: String, folderName: String) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            // Update navigation stack if needed
            if navigationStack.last?.id != folderID {
                // Update the last item or add new one
                if let lastIndex = navigationStack.indices.last {
                    navigationStack[lastIndex] = (id: folderID, name: folderName)
                } else {
                    navigationStack.append((id: folderID, name: folderName))
                }
            }
        }
        
        do {
            var allFiles: [GoogleDriveFile] = []
            
            // If we're at root, also include shared folders
            if folderID == "root" {
                // List files from root
                let rootFiles = try await driveManager.listFiles(in: "root")
                allFiles.append(contentsOf: rootFiles)
                
                // List shared folders
                let sharedFolders = try await driveManager.listSharedFolders()
                allFiles.append(contentsOf: sharedFolders)
            } else {
                // Regular folder listing
                let files = try await driveManager.listFiles(in: folderID)
                allFiles = files
            }
            
            await MainActor.run {
                self.folderContents = allFiles
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func navigateToFolder(folderID: String, folderName: String) {
        navigationStack.append((id: folderID, name: folderName))
        Task {
            await loadFolderContents(folderID: folderID, folderName: folderName)
        }
    }
    
    private func selectM4BFile(fileID: String, folderID: String) {
        onM4BSelected?(fileID, folderID)
        dismiss()
    }
    
    private func iconName(for file: GoogleDriveFile) -> String {
        let name = file.name.lowercased()
        if name.hasSuffix(".m4b") {
            return "music.note"
        } else if name.hasSuffix(".cue") {
            return "doc.text"
        } else if name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") {
            return "photo"
        } else if name.hasSuffix(".nfo") {
            return "info.circle"
        } else {
            return "doc"
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

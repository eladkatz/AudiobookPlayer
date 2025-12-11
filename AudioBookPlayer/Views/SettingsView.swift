import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var skipForwardInterval: TimeInterval
    @State private var skipBackwardInterval: TimeInterval
    @State private var simulateChapters: Bool
    @State private var simulatedChapterLength: TimeInterval
    
    init(appState: AppState) {
        self.appState = appState
        _skipForwardInterval = State(initialValue: appState.playbackSettings.skipForwardInterval)
        _skipBackwardInterval = State(initialValue: appState.playbackSettings.skipBackwardInterval)
        _simulateChapters = State(initialValue: appState.playbackSettings.simulateChapters)
        _simulatedChapterLength = State(initialValue: appState.playbackSettings.simulatedChapterLength)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Skip Intervals")) {
                    // Skip Forward
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Skip Forward")
                            Spacer()
                            Text("\(Int(skipForwardInterval))s")
                                .foregroundColor(.secondary)
                        }
                        
                        Picker("Skip Forward", selection: $skipForwardInterval) {
                            Text("15 seconds").tag(15.0)
                            Text("30 seconds").tag(30.0)
                            Text("45 seconds").tag(45.0)
                            Text("60 seconds").tag(60.0)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: skipForwardInterval) { oldValue, newValue in
                            updateSkipForwardInterval(newValue)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Skip Backward
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Skip Backward")
                            Spacer()
                            Text("\(Int(skipBackwardInterval))s")
                                .foregroundColor(.secondary)
                        }
                        
                        Picker("Skip Backward", selection: $skipBackwardInterval) {
                            Text("15 seconds").tag(15.0)
                            Text("30 seconds").tag(30.0)
                            Text("45 seconds").tag(45.0)
                            Text("60 seconds").tag(60.0)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: skipBackwardInterval) { oldValue, newValue in
                            updateSkipBackwardInterval(newValue)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Chapters")) {
                    Toggle("Simulate Chapters", isOn: $simulateChapters)
                        .onChange(of: simulateChapters) { oldValue, newValue in
                            updateSimulateChapters(newValue)
                        }
                    
                    if simulateChapters {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Chapter Length")
                                Spacer()
                                Text(formatChapterLength(simulatedChapterLength))
                                    .foregroundColor(.secondary)
                            }
                            
                            Picker("Chapter Length", selection: $simulatedChapterLength) {
                                Text("5 minutes").tag(5.0 * 60.0)
                                Text("10 minutes").tag(10.0 * 60.0)
                                Text("15 minutes").tag(15.0 * 60.0)
                                Text("20 minutes").tag(20.0 * 60.0)
                                Text("30 minutes").tag(30.0 * 60.0)
                                Text("60 minutes").tag(60.0 * 60.0)
                            }
                            .pickerStyle(.menu)
                            .onChange(of: simulatedChapterLength) { oldValue, newValue in
                                updateSimulatedChapterLength(newValue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: Text("Storage")) {
                    HStack {
                        Text("Total Books")
                        Spacer()
                        Text("\(appState.books.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Downloaded Books")
                        Spacer()
                        Text("\(appState.books.filter { $0.isDownloaded }.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
    }
    
    // MARK: - Update Methods
    private func updateSkipForwardInterval(_ interval: TimeInterval) {
        appState.playbackSettings.skipForwardInterval = interval
        PersistenceManager.shared.saveSettings(appState.playbackSettings)
    }
    
    private func updateSkipBackwardInterval(_ interval: TimeInterval) {
        appState.playbackSettings.skipBackwardInterval = interval
        PersistenceManager.shared.saveSettings(appState.playbackSettings)
    }
    
    private func updateSimulateChapters(_ enabled: Bool) {
        appState.playbackSettings.simulateChapters = enabled
        PersistenceManager.shared.saveSettings(appState.playbackSettings)
        
        // Reload book to regenerate chapters whenever the setting changes
        if let currentBook = appState.currentBook {
            AudioManager.shared.loadBook(currentBook)
        }
    }
    
    private func updateSimulatedChapterLength(_ length: TimeInterval) {
        appState.playbackSettings.simulatedChapterLength = length
        PersistenceManager.shared.saveSettings(appState.playbackSettings)
        
        // If a book is currently loaded, regenerate chapters with new length
        if let currentBook = appState.currentBook {
            AudioManager.shared.loadBook(currentBook)
        }
    }
    
    private func formatChapterLength(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hr"
            } else {
                return "\(hours) hr \(remainingMinutes) min"
            }
        }
    }
}


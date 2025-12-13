import AVFoundation
import Foundation
import Speech
import SwiftUI

@available(iOS 26.0, *)
class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    
    @Published var isTranscribing: Bool = false
    @Published var progress: Double = 0.0 // 0.0 to 1.0
    @Published var transcribedSentences: [TranscribedSentence] = []
    @Published var errorMessage: String?
    @Published var currentStatus: String = ""
    
    private var analyzer: SpeechAnalyzer?
    private var transcriber: (any SpeechModule)?
    private var tempFileURL: URL?
    private var hasSecurityAccess: Bool = false
    private var securityScopedURL: URL?
    
    private init() {}
    
    // MARK: - Main Transcription Method
    
    func transcribeFirstFiveMinutes(book: Book) async {
        await MainActor.run {
            isTranscribing = true
            progress = 0.0
            transcribedSentences = []
            errorMessage = nil
            currentStatus = "Preparing transcription..."
        }
        
        defer {
            Task { @MainActor in
                isTranscribing = false
                cleanup()
            }
        }
        
        do {
            // Step 1: Get actual file URL (handle security-scoped access)
            let actualURL = try await getActualFileURL(for: book)
            
            // Step 2: Check and download English language model if needed
            await MainActor.run {
                currentStatus = "Checking language model..."
            }
            try await ensureEnglishModelInstalled()
            
            // Step 3: Extract first 5 minutes to temporary file
            await MainActor.run {
                currentStatus = "Extracting audio segment..."
            }
            let tempFile = try await extractFirstFiveMinutes(from: actualURL)
            tempFileURL = tempFile
            
            // Step 4: Perform transcription
            await MainActor.run {
                currentStatus = "Transcribing audio..."
            }
            try await performTranscription(audioFileURL: tempFile)
            
            await MainActor.run {
                currentStatus = "Transcription complete!"
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                currentStatus = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - File Access
    
    private func getActualFileURL(for book: Book) async throws -> URL {
        let filePath = book.fileURL.path
        let resolvedPath = (try? FileManager.default.destinationOfSymbolicLink(atPath: filePath)) ?? filePath
        
        var actualURL: URL
        
        if FileManager.default.fileExists(atPath: filePath) {
            actualURL = book.fileURL
        } else if FileManager.default.fileExists(atPath: resolvedPath) {
            actualURL = URL(fileURLWithPath: resolvedPath)
        } else {
            // Try to find the file in the Books directory
            let booksDir = BookFileManager.shared.getBooksDirectory()
            let fileName = book.fileURL.lastPathComponent
            
            func searchForFile(in directory: URL, fileName: String) -> URL? {
                guard let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    return nil
                }
                
                for case let fileURL as URL in enumerator {
                    let file = fileURL.lastPathComponent
                    if file.lowercased() == fileName.lowercased() ||
                       file.removingPercentEncoding?.lowercased() == fileName.removingPercentEncoding?.lowercased() {
                        return fileURL
                    }
                }
                return nil
            }
            
            if let foundURL = searchForFile(in: booksDir, fileName: fileName) {
                actualURL = foundURL
            } else {
                throw TranscriptionError.fileNotFound
            }
        }
        
        // Handle security-scoped access
        let needsSecurityAccess = !actualURL.path.contains("/Documents/")
        if needsSecurityAccess {
            guard actualURL.startAccessingSecurityScopedResource() else {
                throw TranscriptionError.cannotAccessFile
            }
            hasSecurityAccess = true
            securityScopedURL = actualURL
        }
        
        return actualURL
    }
    
    // MARK: - Language Model Management
    
    private func ensureEnglishModelInstalled() async throws {
        let locale = Locale(identifier: "en_US")
        
        // Check if SpeechTranscriber is available
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.speechNotAvailable
        }
        
        // Check if locale is supported
        let supportedLocales = await SpeechTranscriber.supportedLocales
        let localeIdentifiers = supportedLocales.map { $0.identifier(.bcp47) }
        
        guard localeIdentifiers.contains(locale.identifier(.bcp47)) else {
            throw TranscriptionError.localeNotSupported
        }
        
        // Check if already installed
        let installedLocales = await Set(SpeechTranscriber.installedLocales)
        let installedIdentifiers = installedLocales.map { $0.identifier(.bcp47) }
        
        if installedIdentifiers.contains(locale.identifier(.bcp47)) {
            return // Already installed
        }
        
        // Need to download
        await MainActor.run {
            currentStatus = "Downloading language model..."
        }
        
        // Create a temporary transcriber to request download
        // Use minimal configuration - preset not needed for model download
        let tempTranscriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        
        guard let downloader = try await AssetInventory.assetInstallationRequest(supporting: [tempTranscriber]) else {
            throw TranscriptionError.modelDownloadFailed
        }
        
        try await downloader.downloadAndInstall()
    }
    
    // MARK: - Audio Extraction
    
    private func extractFirstFiveMinutes(from sourceURL: URL) async throws -> URL {
        let asset = AVAsset(url: sourceURL)
        
        // Load duration
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Determine extraction duration (5 minutes or full duration if shorter)
        let extractionDuration = min(5 * 60, durationSeconds)
        let timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: extractionDuration, preferredTimescale: 600))
        
        // Create temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("transcription_\(UUID().uuidString).m4a")
        
        // Remove existing temp file if present
        if FileManager.default.fileExists(atPath: tempFile.path) {
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        // Export using AVAssetExportSession
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.exportFailed(nil)
        }
        
        exportSession.outputURL = tempFile
        exportSession.outputFileType = .m4a
        exportSession.timeRange = timeRange
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            let error = exportSession.error?.localizedDescription ?? "Unknown export error"
            throw TranscriptionError.exportFailed(error)
        }
        
        return tempFile
    }
    
    // MARK: - Transcription
    
    private func performTranscription(audioFileURL: URL) async throws {
        let locale = Locale(identifier: "en_US")
        
        // Create SpeechTranscriber for long-form transcription with automatic punctuation
        // Use full initializer to ensure timestamps are enabled for SRT format
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange] // Enable timestamps for SRT format
        )
        
        self.transcriber = transcriber
        
        // Create analyzer
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        
        // Create AVAudioFile
        let audioFile = try AVAudioFile(forReading: audioFileURL)
        
        // Start analysis
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        
        // Process results sentence by sentence with actual timestamps
        var currentSentence = ""
        var sentenceStartTime: TimeInterval = 0
        var sentenceEndTime: TimeInterval = 0
        
        for try await result in transcriber.results {
            if result.isFinal {
                // Access transcription text - API uses .text property which returns AttributedString
                let transcription = result.text
                
                // Iterate through AttributedString runs to extract timestamps
                for run in transcription.runs {
                    // Get the text for this run's range
                    let runRange = run.range
                    let runText = String(transcription[runRange].characters)
                    
                    // Get timestamp from audioTimeRange attribute
                    var runStartTime: TimeInterval = 0
                    var runEndTime: TimeInterval = 0
                    
                    // Access audioTimeRange attribute from the run
                    // The attribute should be available when attributeOptions includes .audioTimeRange
                    // Try accessing the audioTimeRange attribute directly
                    if let timeRange = run.attributes.audioTimeRange {
                        runStartTime = CMTimeGetSeconds(timeRange.start)
                        runEndTime = runStartTime + CMTimeGetSeconds(timeRange.duration)
                    }
                    
                    // If this is the first run of a sentence and we have a timestamp, record start time
                    if currentSentence.isEmpty && runStartTime > 0 {
                        sentenceStartTime = runStartTime
                    }
                    
                    // Update sentence end time with each run that has a timestamp
                    if runEndTime > 0 {
                        sentenceEndTime = runEndTime
                    }
                    
                    // Add run text to current sentence
                    if currentSentence.isEmpty {
                        currentSentence = runText
                    } else {
                        // Add space if needed (runs might already include spaces)
                        if !runText.isEmpty {
                            let lastCharIsWhitespace = currentSentence.last?.isWhitespace ?? false
                            if !lastCharIsWhitespace {
                                currentSentence += " "
                            }
                        }
                        currentSentence += runText
                    }
                    
                    // Check if sentence is complete (ends with punctuation)
                    if runText.hasSuffix(".") || runText.hasSuffix("!") || runText.hasSuffix("?") {
                        // Capture values before MainActor closure to avoid Swift 6 concurrency issues
                        let sentenceText = currentSentence
                        let startTime = sentenceStartTime > 0 ? sentenceStartTime : 0
                        let endTime = sentenceEndTime > 0 ? sentenceEndTime : startTime
                        
                        // Sentence complete - add to results
                        await MainActor.run {
                            let transcribedSentence = TranscribedSentence(
                                text: sentenceText,
                                startTime: startTime,
                                endTime: endTime
                            )
                            transcribedSentences.append(transcribedSentence)
                            
                            // Update progress based on actual time
                            let totalDuration: TimeInterval = 5 * 60
                            progress = min(endTime / totalDuration, 1.0)
                        }
                        
                        // Reset for next sentence
                        currentSentence = ""
                        sentenceStartTime = 0
                        sentenceEndTime = 0
                    }
                }
            }
        }
        
        // Handle any remaining sentence
        if !currentSentence.isEmpty {
            // Capture values before MainActor closure
            let sentenceText = currentSentence
            let startTime = sentenceStartTime > 0 ? sentenceStartTime : 0
            let endTime = sentenceEndTime > 0 ? sentenceEndTime : (5 * 60)
            
            await MainActor.run {
                let transcribedSentence = TranscribedSentence(
                    text: sentenceText,
                    startTime: startTime,
                    endTime: endTime
                )
                transcribedSentences.append(transcribedSentence)
                progress = 1.0
            }
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        // Clean up temp file
        if let tempFile = tempFileURL {
            try? FileManager.default.removeItem(at: tempFile)
            tempFileURL = nil
        }
        
        // Stop security-scoped access
        if hasSecurityAccess, let url = securityScopedURL {
            url.stopAccessingSecurityScopedResource()
            hasSecurityAccess = false
            securityScopedURL = nil
        }
        
        analyzer = nil
        transcriber = nil
    }
    
    func cancel() {
        Task {
            await analyzer?.cancelAndFinishNow()
            await MainActor.run {
                isTranscribing = false
                cleanup()
            }
        }
    }
}

// MARK: - Supporting Types

@available(iOS 26.0, *)
struct TranscribedSentence: Identifiable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    
    var srtTimeString: String {
        let start = formatSRTTime(startTime)
        let end = formatSRTTime(endTime)
        return "\(start) --> \(end)"
    }
    
    private func formatSRTTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}

@available(iOS 26.0, *)
enum TranscriptionError: LocalizedError {
    case fileNotFound
    case cannotAccessFile
    case speechNotAvailable
    case localeNotSupported
    case modelDownloadFailed
    case exportFailed(String? = nil)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found. Please re-import the book."
        case .cannotAccessFile:
            return "Cannot access audio file. Please re-import the book."
        case .speechNotAvailable:
            return "Speech recognition is not available on this device."
        case .localeNotSupported:
            return "English language is not supported for transcription."
        case .modelDownloadFailed:
            return "Failed to download language model. Please check your internet connection."
        case .exportFailed(let message):
            return message ?? "Failed to extract audio segment."
        }
    }
}

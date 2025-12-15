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
    
    private let database = TranscriptionDatabase.shared
    private var analyzer: SpeechAnalyzer?
    private var transcriber: (any SpeechModule)?
    private var tempFileURL: URL?
    private var hasSecurityAccess: Bool = false
    private var securityScopedURL: URL?
    private var currentBookID: UUID?
    
    private init() {}
    
    // MARK: - Main Transcription Method
    
    func transcribeNextTwoMinutes(book: Book) async {
        await MainActor.run {
            isTranscribing = true
            progress = 0.0
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
            // Step 1: Query database for next start time
            await MainActor.run {
                currentStatus = "Determining next segment..."
            }
            let segmentStartTime = await database.getNextTranscriptionStartTime(bookID: book.id)
            let segmentDuration: TimeInterval = 2 * 60 // 2 minutes
            let segmentEndTime = segmentStartTime + segmentDuration
            
            let startTimeFormatted = formatTime(segmentStartTime)
            let endTimeFormatted = formatTime(segmentEndTime)
            
            await MainActor.run {
                currentStatus = "Transcribing \(startTimeFormatted)-\(endTimeFormatted)..."
            }
            debugLog("🎯 Starting transcription: \(startTimeFormatted) - \(endTimeFormatted)")
            
            // Step 2: Get actual file URL (handle security-scoped access)
            let actualURL = try await getActualFileURL(for: book)
            
            // Step 3: Check and download English language model if needed
            await MainActor.run {
                currentStatus = "Checking language model..."
            }
            try await ensureEnglishModelInstalled()
            
            // Step 4: Extract audio segment to temporary file
            await MainActor.run {
                currentStatus = "Extracting audio segment (\(startTimeFormatted)-\(endTimeFormatted))..."
            }
            let tempFile = try await extractAudioSegment(from: actualURL, startTime: segmentStartTime, duration: segmentDuration)
            tempFileURL = tempFile
            
            // Step 5: Perform transcription
            await MainActor.run {
                currentStatus = "Transcribing audio..."
                currentBookID = book.id
            }
            var sentences = try await performTranscription(audioFileURL: tempFile)
            
            // Step 6: Apply timestamp offset (transcription returns timestamps relative to extracted segment)
            debugLog("🕐 Applying timestamp offset: adding \(segmentStartTime)s to all sentences")
            let offsetSentences = sentences.map { sentence in
                TranscribedSentence(
                    id: sentence.id,
                    text: sentence.text,
                    startTime: sentence.startTime + segmentStartTime,
                    endTime: sentence.endTime + segmentStartTime
                )
            }
            sentences = offsetSentences
            debugLog("✅ Timestamp offset applied: first sentence now starts at \(sentences.first?.startTime ?? 0)s")
            
            // Step 7: Save to database
            await MainActor.run {
                currentStatus = "Inserting to database..."
            }
            let chunk = TranscriptionChunk(
                bookID: book.id,
                startTime: segmentStartTime,
                endTime: segmentEndTime,
                sentences: sentences,
                transcribedAt: Date(),
                isComplete: true
            )
            try await database.insertChunk(chunk)
            
            // Step 8: Load all sentences for display
            await MainActor.run {
                currentStatus = "Loading transcription..."
            }
            // Load all transcribed sentences (no time limit)
            await loadSentencesForDisplay(bookID: book.id, startTime: 0, endTime: Double.greatestFiniteMagnitude)
            
            await MainActor.run {
                currentStatus = "Transcription complete!"
                progress = 1.0
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                currentStatus = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
        debugLog("🔍 Checking English language model installation...")
        
        // Check if SpeechTranscriber is available
        guard SpeechTranscriber.isAvailable else {
            debugLog("❌ SpeechTranscriber is not available")
            throw TranscriptionError.speechNotAvailable
        }
        debugLog("✅ SpeechTranscriber is available")
        
        // Check if locale is supported
        let supportedLocales = await SpeechTranscriber.supportedLocales
        let localeIdentifiers = supportedLocales.map { $0.identifier(.bcp47) }
        debugLog("📋 Supported locales: \(localeIdentifiers)")
        
        guard localeIdentifiers.contains(locale.identifier(.bcp47)) else {
            debugLog("❌ English locale not supported")
            throw TranscriptionError.localeNotSupported
        }
        debugLog("✅ English locale is supported")
        
        // Check if already installed
        let installedLocales = await Set(SpeechTranscriber.installedLocales)
        let installedIdentifiers = installedLocales.map { $0.identifier(.bcp47) }
        debugLog("📦 Installed locales: \(installedIdentifiers)")
        
        if installedIdentifiers.contains(locale.identifier(.bcp47)) {
            debugLog("✅ English model already installed")
            return // Already installed
        }
        
        // Need to download
        debugLog("⬇️ English model not installed, downloading...")
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
            debugLog("❌ Failed to create asset installation request")
            throw TranscriptionError.modelDownloadFailed
        }
        
        debugLog("⬇️ Starting model download...")
        try await downloader.downloadAndInstall()
        debugLog("✅ Model download completed")
        
        // Small delay to ensure model is fully ready
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Verify installation after download
        let verifyInstalled = await Set(SpeechTranscriber.installedLocales)
        let verifyIdentifiers = verifyInstalled.map { $0.identifier(.bcp47) }
        debugLog("🔍 Verifying installation: \(verifyIdentifiers)")
        
        guard verifyIdentifiers.contains(locale.identifier(.bcp47)) else {
            debugLog("❌ Model installation verification failed")
            throw TranscriptionError.modelDownloadFailed
        }
        debugLog("✅ Model installation verified")
        
        // Additional verification: Try to create a test transcriber to ensure locale is allocated
        debugLog("🔍 Testing transcriber creation with installed locale...")
        let _ = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        debugLog("✅ Test transcriber created successfully - locale is allocated")
    }
    
    // MARK: - Audio Extraction
    
    private func extractAudioSegment(from sourceURL: URL, startTime: TimeInterval, duration: TimeInterval) async throws -> URL {
        let asset = AVAsset(url: sourceURL)
        
        // Load duration
        let assetDuration = try await asset.load(.duration)
        let assetDurationSeconds = CMTimeGetSeconds(assetDuration)
        
        // Ensure we don't exceed the asset duration
        let actualStartTime = max(0, startTime)
        let remainingDuration = assetDurationSeconds - actualStartTime
        let extractionDuration = min(duration, remainingDuration)
        
        guard extractionDuration > 0 else {
            throw TranscriptionError.exportFailed("Cannot extract segment: start time exceeds audio duration")
        }
        
        let timeRange = CMTimeRange(
            start: CMTime(seconds: actualStartTime, preferredTimescale: 600),
            duration: CMTime(seconds: extractionDuration, preferredTimescale: 600)
        )
        
        debugLog("📁 Extracting audio segment: start=\(actualStartTime)s, duration=\(extractionDuration)s")
        
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
        
        debugLog("✅ Audio segment extracted successfully")
        return tempFile
    }
    
    // MARK: - Transcription
    
    private func performTranscription(audioFileURL: URL) async throws -> [TranscribedSentence] {
        let locale = Locale(identifier: "en_US")
        debugLog("🎤 Starting transcription for audio file: \(audioFileURL.lastPathComponent)")
        
        // Verify locale is installed before creating transcriber
        let installedLocales = await Set(SpeechTranscriber.installedLocales)
        let installedIdentifiers = installedLocales.map { $0.identifier(.bcp47) }
        debugLog("🔍 Checking installed locales before creating transcriber: \(installedIdentifiers)")
        
        guard installedIdentifiers.contains(locale.identifier(.bcp47)) else {
            debugLog("❌ English locale not installed, cannot create transcriber")
            throw TranscriptionError.localeNotSupported
        }
        
        // Create SpeechTranscriber for long-form transcription with automatic punctuation
        // Use full initializer to ensure timestamps are enabled for SRT format
        debugLog("🔧 Creating SpeechTranscriber...")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange] // Enable timestamps for SRT format
        )
        debugLog("✅ SpeechTranscriber created")
        
        await MainActor.run {
            self.transcriber = transcriber
        }
        
        // Create analyzer
        debugLog("🔧 Creating SpeechAnalyzer...")
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        debugLog("✅ SpeechAnalyzer created")
        await MainActor.run {
            self.analyzer = analyzer
        }
        
        // Create AVAudioFile
        debugLog("📁 Opening audio file...")
        let audioFile = try AVAudioFile(forReading: audioFileURL)
        let fileDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        debugLog("✅ Audio file opened: duration = \(fileDuration) seconds, sample rate = \(audioFile.fileFormat.sampleRate) Hz")
        
        // Start analysis
        debugLog("🚀 Starting audio analysis...")
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            debugLog("✅ Analysis sequence completed, finalizing...")
            try await analyzer.finalizeAndFinish(through: lastSample)
            debugLog("✅ Analysis finalized")
        } else {
            debugLog("⚠️ Analysis sequence returned nil, cancelling...")
            await analyzer.cancelAndFinishNow()
        }
        
        // Process results sentence by sentence with actual timestamps
        debugLog("📝 Processing transcription results...")
        var sentences: [TranscribedSentence] = []
        var currentSentence = ""
        var sentenceStartTime: TimeInterval = 0
        var sentenceEndTime: TimeInterval = 0
        var resultCount = 0
        
        for try await result in transcriber.results {
            resultCount += 1
            debugLog("📨 Received result #\(resultCount), isFinal: \(result.isFinal)")
            
            if result.isFinal {
                // Access transcription text - API uses .text property which returns AttributedString
                let transcription = result.text
                let transcriptionString = String(transcription.characters)
                debugLog("📝 Final transcription text length: \(transcriptionString.count) characters")
                debugLog("📝 Transcription preview: \(transcriptionString.prefix(100))")
                debugLog("📝 Number of runs: \(transcription.runs.count)")
                
                // Iterate through AttributedString runs to extract timestamps
                var runIndex = 0
                for run in transcription.runs {
                    runIndex += 1
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
                        debugLog("  Run #\(runIndex): '\(runText.prefix(30))...' [\(runStartTime)s - \(runEndTime)s]")
                    } else {
                        debugLog("  Run #\(runIndex): '\(runText.prefix(30))...' [NO TIMESTAMP]")
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
                        let sentenceText = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                        let startTime = sentenceStartTime > 0 ? sentenceStartTime : 0
                        let endTime = sentenceEndTime > 0 ? sentenceEndTime : startTime
                        
                        if !sentenceText.isEmpty {
                            debugLog("✅ Completed sentence #\(sentences.count + 1): '\(sentenceText.prefix(50))...' [\(startTime)s - \(endTime)s]")
                            
                            // Sentence complete - add to results
                            let transcribedSentence = TranscribedSentence(
                                text: sentenceText,
                                startTime: startTime,
                                endTime: endTime
                            )
                            
                            // Verify sentence was created correctly
                            if transcribedSentence.text != sentenceText {
                                debugLog("⚠️ WARNING: Sentence text mismatch! Original: '\(sentenceText.prefix(30))...', Stored: '\(transcribedSentence.text.prefix(30))...'")
                            }
                            if transcribedSentence.text.isEmpty {
                                debugLog("⚠️ WARNING: TranscribedSentence has empty text even though sentenceText was not empty!")
                            }
                            
                            sentences.append(transcribedSentence)
                            debugLog("   Sentence added, total count: \(sentences.count), sentence.id=\(transcribedSentence.id.uuidString)")
                        } else {
                            debugLog("⚠️ Empty sentence detected, skipping")
                        }
                        
                        // Update progress on main thread
                        await MainActor.run {
                            let totalDuration: TimeInterval = 2 * 60 // 2 minutes
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
            let sentenceText = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let startTime = sentenceStartTime > 0 ? sentenceStartTime : 0
            let endTime = sentenceEndTime > 0 ? sentenceEndTime : (2 * 60) // 2 minutes
            
            if !sentenceText.isEmpty {
                debugLog("✅ Final sentence #\(sentences.count + 1): '\(sentenceText.prefix(50))...' [\(startTime)s - \(endTime)s]")
                
                let transcribedSentence = TranscribedSentence(
                    text: sentenceText,
                    startTime: startTime,
                    endTime: endTime
                )
                
                // Verify sentence was created correctly
                if transcribedSentence.text != sentenceText {
                    debugLog("⚠️ WARNING: Final sentence text mismatch!")
                }
                if transcribedSentence.text.isEmpty {
                    debugLog("⚠️ WARNING: Final TranscribedSentence has empty text!")
                }
                
                sentences.append(transcribedSentence)
                debugLog("   Final sentence added, total count: \(sentences.count), sentence.id=\(transcribedSentence.id.uuidString)")
            } else {
                debugLog("⚠️ Final sentence is empty, skipping")
            }
            
            await MainActor.run {
                progress = 1.0
            }
        }
        
        debugLog("✅ Transcription complete: \(sentences.count) sentences extracted")
        if sentences.isEmpty {
            debugLog("⚠️ WARNING: No sentences were extracted from transcription!")
        }
        
        return sentences
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
    
    // MARK: - Database Methods
    
    func loadSentencesForDisplay(bookID: UUID, startTime: TimeInterval, endTime: TimeInterval) async {
        // If endTime is very large (Double.greatestFiniteMagnitude), load all sentences
        let actualEndTime = endTime >= Double.greatestFiniteMagnitude / 2 ? Double.greatestFiniteMagnitude : endTime
        debugLog("📥 Loading sentences for display: bookID=\(bookID.uuidString), range=\(startTime)s - \(actualEndTime)s")
        
        let sentences = await database.loadSentences(
            bookID: bookID,
            startTime: startTime,
            endTime: actualEndTime
        )
        
        debugLog("📥 Database returned \(sentences.count) sentences")
        if sentences.isEmpty {
            debugLog("⚠️ No sentences loaded from database!")
        } else {
            debugLog("📥 First sentence: id=\(sentences[0].id.uuidString), text='\(sentences[0].text.prefix(50))...', start=\(sentences[0].startTime)s, end=\(sentences[0].endTime)s")
            debugLog("📥 Last sentence: id=\(sentences[sentences.count - 1].id.uuidString), text='\(sentences[sentences.count - 1].text.prefix(50))...', start=\(sentences[sentences.count - 1].startTime)s, end=\(sentences[sentences.count - 1].endTime)s")
            
            // Check for empty sentences
            let emptyCount = sentences.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            if emptyCount > 0 {
                debugLog("⚠️ Found \(emptyCount) empty sentences out of \(sentences.count)")
            }
        }
        
        await MainActor.run {
            debugLog("📥 Setting transcribedSentences to \(sentences.count) sentences")
            transcribedSentences = sentences
            debugLog("📥 transcribedSentences.count is now \(transcribedSentences.count)")
        }
    }
    
    func findCurrentSentence(bookID: UUID, atTime: TimeInterval) async -> UUID? {
        let sentence = await database.findSentence(bookID: bookID, atTime: atTime)
        return sentence?.id
    }
    
    func getTranscriptionProgress(bookID: UUID) async -> TimeInterval {
        return await database.getTranscriptionProgress(bookID: bookID)
    }
    
    // MARK: - Debug Logging
    
    private func debugLog(_ message: String) {
        print("🔊 [TranscriptionManager] \(message)")
    }
}

// MARK: - Supporting Types

@available(iOS 26.0, *)
struct TranscribedSentence: Identifiable, Codable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    
    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
    
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



import Foundation
import AVFoundation

/// Utility for parsing chapters from audiobook files
///
/// **Chapter Source Priority (IMPORTANT):**
/// 1. M4B embedded chapter metadata (highest priority - when implemented)
/// 2. CUE file chapters (when implemented)
/// 3. Multiple MP3 files (when implemented - each file = one chapter)
/// 4. Simulated chapters (LAST RESORT - only if no other source available)
///
/// **CRITICAL RISK MITIGATION:**
/// - **NEVER** merge multiple chapter sources (e.g., CUE + simulated)
/// - If CUE file exists, use ONLY CUE file chapters
/// - If M4B metadata exists, use ONLY M4B chapters
/// - Simulated chapters are ONLY used when NO other chapter source is available
/// - This ensures chapter indices remain stable across app sessions
/// - Mixing sources would cause chapter index mismatches and transcription data loss
class ChapterParser {
    static let shared = ChapterParser()
    
    private init() {}
    
    /// Parse chapters from an audio asset
    ///
    /// **Chapter Source Priority:**
    /// 1. M4B embedded metadata (when implemented)
    /// 2. CUE file (when implemented) - check `book.associatedFiles` for `.cue` files
    /// 3. Multiple MP3 files (when implemented)
    /// 4. Simulated chapters (LAST RESORT - only if none of the above are available)
    ///
    /// - Parameters:
    ///   - asset: The AVAsset to parse chapters from
    ///   - duration: The duration of the audio file
    ///   - bookID: The book ID (currently unused, kept for future use)
    /// - Returns: Array of Chapter objects, sorted by startTime
    func parseChapters(from asset: AVAsset, duration: TimeInterval, bookID: UUID) -> [Chapter] {
        var parsedChapters: [Chapter] = []
        
        // TODO: Step 1 - Parse M4B embedded chapter metadata (highest priority)
        // When implemented, this should populate parsedChapters from AVAsset chapter metadata
        // If chapters are found here, return immediately (do NOT check CUE or simulate)
        
        // TODO: Step 2 - Parse CUE file if available (second priority)
        // When implemented:
        //   - Check book.associatedFiles for .cue files
        //   - Parse CUE file to extract chapters
        //   - If chapters found, return immediately (do NOT simulate)
        //   - CRITICAL: Never use both CUE and simulated chapters
        
        // TODO: Step 3 - Multiple MP3 files (when implemented)
        // If book consists of multiple MP3 files, each file = one chapter
        // This would be checked before falling back to simulation
        
        // Step 4 - Fallback: Create single placeholder chapter
        // This is a temporary fallback until proper chapter parsing is implemented
        // Note: Chapter.id is only used for SwiftUI Identifiable conformance
        // Transcription system uses chapter_index (array position) instead
        parsedChapters.append(Chapter(
            id: UUID(), // UUID for Identifiable conformance only - transcription uses chapter_index
            title: "Chapter 1",
            startTime: 0,
            duration: duration
        ))
        
        // Step 5 - LAST RESORT: Simulated chapters
        // ONLY use if:
        //   - No M4B metadata found
        //   - No CUE file available
        //   - Not multiple MP3 files
        //   - User has enabled simulated chapters in settings
        //   - AND only a single placeholder chapter exists
        //
        // **CRITICAL:** This is a last resort. Once CUE/M4B parsing is implemented,
        // simulated chapters should NEVER be used if those sources are available.
        if parsedChapters.count <= 1 {
            let settings = PersistenceManager.shared.loadSettings()
            if settings.simulateChapters {
                parsedChapters = generateSimulatedChapters(duration: duration, chapterLength: settings.simulatedChapterLength, bookID: bookID)
            }
        }
        
        // Ensure chapters are sorted by startTime for consistent indexing
        parsedChapters.sort { $0.startTime < $1.startTime }
        
        return parsedChapters
    }
    
    // MARK: - Simulated Chapters (LAST RESORT)
    
    /// Generate simulated chapters by dividing the book into equal-length segments
    ///
    /// **WARNING: This is a LAST RESORT fallback.**
    /// - Only used when NO other chapter source is available (no M4B metadata, no CUE file, not multiple files)
    /// - Simulated chapters are NOT real chapters - they're artificial divisions for navigation
    /// - Once proper chapter parsing (M4B/CUE) is implemented, this should NEVER be used if those sources exist
    /// - Mixing simulated chapters with real chapters (CUE/M4B) would break chapter indices and transcription data
    ///
    /// - Parameters:
    ///   - duration: Total duration of the book
    ///   - chapterLength: Desired length of each simulated chapter
    ///   - bookID: Book ID (currently unused, kept for consistency)
    /// - Returns: Array of simulated Chapter objects
    private func generateSimulatedChapters(duration: TimeInterval, chapterLength: TimeInterval, bookID: UUID) -> [Chapter] {
        guard duration > 0 && chapterLength > 0 else {
            // Fallback to single chapter if invalid duration or chapter length
            // Note: Chapter.id is only for SwiftUI Identifiable - transcription uses chapter_index
            return [Chapter(id: UUID(), title: "Chapter 1", startTime: 0, duration: duration)]
        }
        
        var chapters: [Chapter] = []
        let numberOfChapters = Int(ceil(duration / chapterLength))
        
        for i in 0..<numberOfChapters {
            let startTime = TimeInterval(i) * chapterLength
            let remainingDuration = duration - startTime
            let chapterDuration = min(chapterLength, remainingDuration)
            
            // Only add chapter if it has positive duration
            if chapterDuration > 0 {
                // Note: Chapter.id is only for SwiftUI Identifiable - transcription uses chapter_index
                chapters.append(Chapter(
                    id: UUID(), // UUID for Identifiable conformance only - transcription uses chapter_index
                    title: "Chapter \(i + 1)",
                    startTime: startTime,
                    duration: chapterDuration
                ))
            }
        }
        
        // Ensure at least one chapter exists
        if chapters.isEmpty {
            // Note: Chapter.id is only for SwiftUI Identifiable - transcription uses chapter_index
            chapters.append(Chapter(id: UUID(), title: "Chapter 1", startTime: 0, duration: duration))
        }
        
        return chapters
    }
}

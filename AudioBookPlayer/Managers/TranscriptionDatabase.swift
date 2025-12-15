import Foundation
import GRDB

@available(iOS 26.0, *)
class TranscriptionDatabase: @unchecked Sendable {
    static let shared = TranscriptionDatabase()
    
    private var dbQueue: DatabaseQueue?
    
    private init() {
        setupDatabase()
    }
    
    // MARK: - Database Setup
    
    private func setupDatabase() {
        let fileURL = databaseURL()
        
        // Create directory if needed
        let directoryURL = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        
        do {
            // Open or create database
            dbQueue = try DatabaseQueue(path: fileURL.path)
            
            // Create tables
            try dbQueue?.write { db in
                try createTables(db: db)
            }
            
            print("✅ [TranscriptionDatabase] Database initialized successfully")
        } catch {
            print("❌ [TranscriptionDatabase] Failed to setup database: \(error)")
            // Try to recreate if setup fails
            try? FileManager.default.removeItem(at: fileURL)
            do {
                dbQueue = try DatabaseQueue(path: fileURL.path)
                try dbQueue?.write { db in
                    try createTables(db: db)
                }
                print("✅ [TranscriptionDatabase] Database recreated successfully")
            } catch {
                print("❌ [TranscriptionDatabase] Failed to recreate database: \(error)")
            }
        }
    }
    
    private func databaseURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("transcription.db")
    }
    
    private func createTables(db: Database) throws {
        // Create sentences table
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS sentences (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL,
                text TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                chunk_id TEXT NOT NULL,
                created_at REAL NOT NULL
            );
        """)
        
        // Create chunks table
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                created_at REAL NOT NULL,
                is_complete INTEGER NOT NULL DEFAULT 1
            );
        """)
        
        // Create indexes for efficient queries
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_sentences_book_time 
            ON sentences(book_id, start_time);
        """)
        
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_sentences_book_end_time 
            ON sentences(book_id, end_time);
        """)
        
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_chunks_book_time 
            ON chunks(book_id, start_time);
        """)
        
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_chunks_book_end_time 
            ON chunks(book_id, end_time);
        """)
        
        print("✅ [TranscriptionDatabase] Tables and indexes created")
    }
    
    // MARK: - Public Methods
    
    func loadSentences(
        bookID: UUID,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async -> [TranscribedSentence] {
        guard let dbQueue = dbQueue else {
            print("❌ [TranscriptionDatabase] Database not initialized")
            return []
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let sentences = try dbQueue.read { db -> [TranscribedSentence] in
                    let bookIDString = bookID.uuidString
                    print("💾 [TranscriptionDatabase] Loading sentences: bookID=\(bookIDString), range=\(startTime)s - \(endTime)s")
                    
                    let rows = try Row.fetchAll(
                        db,
                        sql: """
                            SELECT id, book_id, text, start_time, end_time, chunk_id, created_at
                            FROM sentences
                            WHERE book_id = ? AND start_time >= ? AND start_time < ?
                            ORDER BY start_time ASC
                        """,
                        arguments: [bookIDString, startTime, endTime]
                    )
                    
                    let sentences = rows.compactMap { row -> TranscribedSentence? in
                        guard let idString = row["id"] as String?,
                              let id = UUID(uuidString: idString),
                              let text = row["text"] as String?,
                              let startTime = row["start_time"] as Double?,
                              let endTime = row["end_time"] as Double? else {
                            return nil
                        }
                        return TranscribedSentence(
                            id: id,
                            text: text,
                            startTime: startTime,
                            endTime: endTime
                        )
                    }
                    
                    print("💾 [TranscriptionDatabase] Loaded \(sentences.count) sentences")
                    return sentences
                }
                continuation.resume(returning: sentences)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to load sentences: \(error)")
                continuation.resume(returning: [])
            }
        }
    }
    
    func findSentence(bookID: UUID, atTime: TimeInterval) async -> TranscribedSentence? {
        guard let dbQueue = dbQueue else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let sentence = try dbQueue.read { db -> TranscribedSentence? in
                    let bookIDString = bookID.uuidString
                    
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT id, book_id, text, start_time, end_time, chunk_id, created_at
                            FROM sentences
                            WHERE book_id = ? AND start_time <= ? AND end_time > ?
                            ORDER BY start_time DESC
                            LIMIT 1
                        """,
                        arguments: [bookIDString, atTime, atTime]
                    )
                    
                    guard let row = row,
                          let idString = row["id"] as String?,
                          let id = UUID(uuidString: idString),
                          let text = row["text"] as String?,
                          let startTime = row["start_time"] as Double?,
                          let endTime = row["end_time"] as Double? else {
                        return nil
                    }
                    
                    return TranscribedSentence(
                        id: id,
                        text: text,
                        startTime: startTime,
                        endTime: endTime
                    )
                }
                continuation.resume(returning: sentence)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to find sentence: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    func insertChunk(_ chunk: TranscriptionChunk) async throws {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.databaseNotInitialized
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try dbQueue.write { db in
                    let bookIDString = chunk.bookID.uuidString
                    let chunkIDString = chunk.id.uuidString
                    let createdAt = chunk.transcribedAt.timeIntervalSince1970
                    
                    print("💾 [TranscriptionDatabase] Inserting chunk: \(chunkIDString), \(chunk.sentences.count) sentences, range: \(chunk.startTime)s - \(chunk.endTime)s")
                    
                    // Insert chunk metadata
                    try db.execute(
                        sql: """
                            INSERT OR REPLACE INTO chunks (id, book_id, start_time, end_time, created_at, is_complete)
                            VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            chunkIDString,
                            bookIDString,
                            chunk.startTime,
                            chunk.endTime,
                            createdAt,
                            chunk.isComplete ? 1 : 0
                        ]
                    )
                    print("✅ [TranscriptionDatabase] Chunk metadata inserted")
                    
                    // Delete existing sentences in this time range
                    try db.execute(
                        sql: """
                            DELETE FROM sentences
                            WHERE book_id = ? AND start_time >= ? AND start_time < ?
                        """,
                        arguments: [bookIDString, chunk.startTime, chunk.endTime]
                    )
                    print("💾 [TranscriptionDatabase] Deleted existing sentences in time range")
                    
                    // Insert sentences
                    var insertedCount = 0
                    for sentence in chunk.sentences {
                        let sentenceIDString = sentence.id.uuidString
                        
                        try db.execute(
                            sql: """
                                INSERT OR REPLACE INTO sentences 
                                (id, book_id, text, start_time, end_time, chunk_id, created_at)
                                VALUES (?, ?, ?, ?, ?, ?, ?)
                            """,
                            arguments: [
                                sentenceIDString,
                                bookIDString,
                                sentence.text,
                                sentence.startTime,
                                sentence.endTime,
                                chunkIDString,
                                createdAt
                            ]
                        )
                        insertedCount += 1
                    }
                    
                    print("✅ [TranscriptionDatabase] Inserted \(insertedCount) sentences successfully")
                    continuation.resume()
                }
            } catch {
                print("❌ [TranscriptionDatabase] Failed to insert chunk: \(error)")
                continuation.resume(throwing: DatabaseError.insertFailed(error.localizedDescription))
            }
        }
    }
    
    func getTranscriptionProgress(bookID: UUID) async -> TimeInterval {
        guard let dbQueue = dbQueue else {
            return 0.0
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let progress = try dbQueue.read { db -> TimeInterval in
                    let bookIDString = bookID.uuidString
                    
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT MAX(end_time) as max_time
                            FROM sentences
                            WHERE book_id = ?
                        """,
                        arguments: [bookIDString]
                    )
                    
                    return (row?["max_time"] as Double?) ?? 0.0
                }
                continuation.resume(returning: progress)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to get progress: \(error)")
                continuation.resume(returning: 0.0)
            }
        }
    }
    
    func getNextTranscriptionStartTime(bookID: UUID) async -> TimeInterval {
        guard let dbQueue = dbQueue else {
            return 0.0
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let startTime = try dbQueue.read { db -> TimeInterval in
                    let bookIDString = bookID.uuidString
                    
                    // Find the latest chunk end time
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT MAX(end_time) as max_end_time
                            FROM chunks
                            WHERE book_id = ?
                        """,
                        arguments: [bookIDString]
                    )
                    
                    if let maxEndTime = row?["max_end_time"] as Double? {
                        return maxEndTime
                    }
                    
                    return 0.0
                }
                
                if startTime == 0.0 {
                    print("💾 [TranscriptionDatabase] No existing chunks, starting from 0:00")
                } else {
                    print("💾 [TranscriptionDatabase] Next transcription start time: \(startTime)s")
                }
                
                continuation.resume(returning: startTime)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to get next start time: \(error)")
                continuation.resume(returning: 0.0)
            }
        }
    }
    
    func getChunkCount(bookID: UUID) async -> Int {
        guard let dbQueue = dbQueue else {
            return 0
        }
        
        return await withCheckedContinuation { continuation in
            do {
                let count = try dbQueue.read { db -> Int in
                    let bookIDString = bookID.uuidString
                    
                    let row = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT COUNT(*) as count
                            FROM chunks
                            WHERE book_id = ?
                        """,
                        arguments: [bookIDString]
                    )
                    
                    return Int((row?["count"] as Int64?) ?? 0)
                }
                continuation.resume(returning: count)
            } catch {
                print("❌ [TranscriptionDatabase] Failed to get chunk count: \(error)")
                continuation.resume(returning: 0)
            }
        }
    }
    
    func deleteTranscription(bookID: UUID) async {
        guard let dbQueue = dbQueue else {
            return
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                try dbQueue.write { db in
                    let bookIDString = bookID.uuidString
                    
                    // Delete sentences
                    try db.execute(
                        sql: "DELETE FROM sentences WHERE book_id = ?",
                        arguments: [bookIDString]
                    )
                    
                    // Delete chunks
                    try db.execute(
                        sql: "DELETE FROM chunks WHERE book_id = ?",
                        arguments: [bookIDString]
                    )
                    
                    print("✅ [TranscriptionDatabase] Deleted transcription data for book \(bookIDString)")
                }
                continuation.resume()
            } catch {
                print("❌ [TranscriptionDatabase] Failed to delete transcription: \(error)")
                continuation.resume()
            }
        }
    }
    
    func clearTranscription(bookID: UUID) async {
        await deleteTranscription(bookID: bookID)
    }
}

// MARK: - Database Errors

enum DatabaseError: LocalizedError {
    case databaseNotInitialized
    case insertFailed(String)
    case queryFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .databaseNotInitialized:
            return "Database not initialized"
        case .insertFailed(let message):
            return "Failed to insert: \(message)"
        case .queryFailed(let message):
            return "Failed to query: \(message)"
        }
    }
}



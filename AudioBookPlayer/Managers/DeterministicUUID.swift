import Foundation
import CryptoKit

/// Utility for generating deterministic UUIDs
enum DeterministicUUID {
    /// Generate a deterministic UUID from a string seed
    /// Uses SHA256 hash to ensure consistency
    static func fromString(_ string: String) -> UUID {
        // Hash the input string using SHA256
        let data = string.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        
        // Take first 16 bytes for UUID
        var uuidBytes = [UInt8](hash.prefix(16))
        
        // Set version (4 bits) and variant (2 bits) to make it a valid UUID v4-like
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x40 // Version 4
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80 // Variant 10
        
        // Create UUID from bytes
        let uuidData = Data(uuidBytes)
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        _ = uuidData.withUnsafeBytes { bytes in
            memcpy(&uuid, bytes.baseAddress, 16)
        }
        
        return UUID(uuid: uuid)
    }
    
    /// Generate a deterministic UUID for a book based on file path
    static func forBook(filePath: String) -> UUID {
        // Use normalized file path as seed
        // Normalize by using absolute path and resolving symlinks if possible
        let normalizedPath: String
        if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: filePath) {
            normalizedPath = resolved
        } else {
            normalizedPath = filePath
        }
        return fromString("book:\(normalizedPath)")
    }
    
    /// Generate a deterministic UUID for a chapter based on bookID, startTime, and endTime
    static func forChapter(bookID: UUID, startTime: TimeInterval, endTime: TimeInterval) -> UUID {
        // Use bookID, startTime, and endTime as seed
        // Round times to avoid floating point precision issues
        let roundedStart = round(startTime * 10) / 10 // Round to 0.1s
        let roundedEnd = round(endTime * 10) / 10
        let seed = "chapter:\(bookID.uuidString):\(roundedStart):\(roundedEnd)"
        return fromString(seed)
    }
}

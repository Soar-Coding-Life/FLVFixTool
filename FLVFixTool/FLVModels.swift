//
//  FLVModels.swift
//  FLVFixTool
//
//  Created by Gemini on 2025/8/16.
//

import Foundation

// Represents the entire parsed FLV file.
struct FLVFile {
    let fileName: String
    let sourceURL: URL
    
    let header: FLVHeader
    var metadata: [String: Any]
    let tags: [FLVTag]
}

// Represents the 9-byte FLV header.
struct FLVHeader {
    let signature: String
    let version: UInt8
    let hasAudio: Bool
    let hasVideo: Bool
    let headerSize: UInt32
}

// Represents a single FLV tag.
struct FLVTag: Identifiable {
    let id = UUID()
    let offset: Int
    let type: TagType
    let dataSize: UInt32
    let timestamp: UInt32
    let streamId: UInt32
    
    let details: TagDetails
    var analysis: String? // For frame drop warnings
    
    enum TagType: String {
        case audio = "Audio"
        case video = "Video"
        case script = "Script Data"
        case unknown = "Unknown"
    }
}

// An enum with associated values to hold the specific details for each tag type.
enum TagDetails {
    case audio(AudioDetails)
    case video(VideoDetails)
    case script(ScriptDetails)
    case unknown
}

// MARK: - Tag Detail Structs

struct AudioDetails {
    let format: String
    let sampleRate: String
    let sampleSize: String
    let channels: String
    
    // AAC Specific
    let aacPacketType: String?
    let audioObjectType: String?
}

struct VideoDetails {
    let frameType: String
    let codec: String
    
    // AVC (H.264) Specific
    let avcPacketType: String?
    let compositionTimeOffset: Int32?
}

struct ScriptDetails {
    let name: String
    let value: Any
}

// MARK: - Detail Model String Representations
extension AudioDetails {
    func toStringArray() -> [String] {
        var lines = [
            "Format: \(format)",
            "Sample Rate: \(sampleRate)",
            "Sample Size: \(sampleSize)",
            "Channels: \(channels)"
        ]
        if let type = aacPacketType {
            lines.append("AAC Packet Type: \(type)")
        }
        if let type = audioObjectType {
            lines.append("Audio Object Type: \(type)")
        }
        return lines
    }
}

extension VideoDetails {
    func toStringArray() -> [String] {
        var lines = [
            "Frame Type: \(frameType)",
            "Codec: \(codec)"
        ]
        if let type = avcPacketType {
            lines.append("AVC Packet Type: \(type)")
        }
        if let offset = compositionTimeOffset {
            lines.append("Composition Time Offset: \(offset)")
        }
        return lines
    }
}

extension ScriptDetails {
    func toStringArray() -> [String] {
        return [
            "Name: \(name)",
            "Value: \(String(describing: value))"
        ]
    }
}

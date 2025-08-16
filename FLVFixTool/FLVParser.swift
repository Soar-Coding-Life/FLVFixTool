//
//  FLVParser.swift
//  FLVFixTool
//
//  Created by 王贵彬 on 2025/8/16.
//

import Foundation

// MARK: - FLV Parser
class FLVParser {
    
    enum ParserError: String, Error {
        case invalidSignature = "Invalid FLV signature."
        case dataTooShort = "Data is too short to parse."
        case metadataNotFound = "onMetaData script tag not found."
    }

    private var reader: DataReader!
    private var metadata: [String: Any] = [:]

    func parse(url: URL) throws -> FLVFile {
        let data = try Data(contentsOf: url)
        self.reader = DataReader(data: data)
        
        let header = try parseHeader()
        var tags: [FLVTag] = []
        
        // First pass: find metadata to provide context for the full tag parse.
        try findMetadata()
        reader.seek(to: Int(header.headerSize) + 4) // Reset for second pass
        
        // Second pass: parse all tags.
        while !reader.isAtEnd {
            let tagStartOffset = reader.offset
            
            // A full tag requires at least 15 bytes (11 header + 4 prevTagSize)
            guard reader.remainingBytes >= 15 else { break }
            
            let tagHeaderData = try reader.readBytes(count: 11)
            let dataSize = UInt32(tagHeaderData[1]) << 16 | UInt32(tagHeaderData[2]) << 8 | UInt32(tagHeaderData[3])
            
            // Ensure the full tag (header + data + prevTagSize) is present
            guard reader.remainingBytes >= Int(dataSize) + 4 else { break }
            
            let tagData = try reader.readBytes(count: Int(dataSize))
            _ = try reader.readUInt32() // PreviousTagSize
            
            let tag = FLVTag(
                offset: tagStartOffset,
                headerData: tagHeaderData,
                tagData: tagData,
                globalMetadata: self.metadata
            )
            tags.append(tag)
        }
        
        let analyzedTags = analyzeTags(tags: tags)
        
        return FLVFile(
            fileName: url.lastPathComponent,
            sourceURL: url,
            header: header,
            metadata: self.metadata,
            tags: analyzedTags
        )
    }
    
    private func findMetadata() throws {
        let originalOffset = reader.offset
        defer { reader.seek(to: originalOffset) } // Ensure we don't affect the main parse
        
        // An FLV file must have at least a 9-byte header to be valid.
        guard reader.data.count >= 9 else {
            return // Not a throwable error, just means no metadata can exist.
        }
        
        // The header size is a 4-byte field starting at offset 5.
        let headerSize = UInt32(bigEndian: reader.data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self) })
        
        // Start searching for tags after the header and the 4-byte "PreviousTagSize0".
        reader.seek(to: Int(headerSize) + 4)
        
        while !reader.isAtEnd {
            guard reader.remainingBytes >= 11 else { break }
            let tagHeader = try reader.peekBytes(count: 11)
            let tagType = tagHeader[0]
            let dataSize = Int(UInt32(tagHeader[1]) << 16 | UInt32(tagHeader[2]) << 8 | UInt32(tagHeader[3]))
            
            try reader.advance(by: 11)
            guard reader.remainingBytes >= dataSize + 4 else { break }
            
            if tagType == 18 { // Script Data
                let tagData = try reader.readBytes(count: dataSize)
                let scriptDetails = ScriptDetails(data: tagData)
                if scriptDetails.name == "onMetaData", let metaDict = scriptDetails.value as? [String: Any] {
                    self.metadata = metaDict
                    return // Found it, we're done.
                }
            } else {
                try reader.advance(by: dataSize)
            }
            try reader.advance(by: 4) // Skip PreviousTagSize
        }
    }

    private func parseHeader() throws -> FLVHeader {
        let signature = try reader.readString(length: 3)
        guard signature == "FLV" else { throw ParserError.invalidSignature }
        
        let version = try reader.readUInt8()
        let flags = try reader.readUInt8()
        let headerSize = try reader.readUInt32()
        
        return FLVHeader(
            signature: signature,
            version: version,
            hasAudio: (flags & 0x04) != 0,
            hasVideo: (flags & 0x01) != 0,
            headerSize: headerSize
        )
    }
    
    private func analyzeTags(tags: [FLVTag]) -> [FLVTag] {
        var analyzedTags = tags
        
        if let framerate = metadata["framerate"] as? Double, framerate > 0 {
            let videoTags = analyzedTags.filter { $0.type == .video }
            let expectedInterval = 1000 / framerate
            let threshold = expectedInterval * 2.0
            
            for i in 1..<videoTags.count {
                let prevTag = videoTags[i-1]
                let currTag = videoTags[i]
                let gap = Double(currTag.timestamp - prevTag.timestamp)
                
                if gap > threshold {
                    let droppedFrames = round(gap / expectedInterval) - 1
                    if let index = analyzedTags.firstIndex(where: { $0.id == currTag.id }), droppedFrames > 0 {
                        analyzedTags[index].analysis = "Timestamp jump of \(Int(gap))ms. Possible \(Int(droppedFrames)) dropped frames."
                    }
                }
            }
        }
        return analyzedTags
    }
    
    // MARK: - Public Utilities
    
    func generateNewFLV(originalURL: URL, newMetadata: [String: Any]) throws -> Data {
        let originalData = try Data(contentsOf: originalURL)
        let reader = DataReader(data: originalData)
        let writer = DataWriter()

        // 1. Write Header and PreviousTagSize0
        let headerData = try reader.readBytes(count: 9)
        let headerSize = UInt32(bigEndian: headerData.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self) })
        writer.write(headerData)
        
        // The FLV spec says the header is at least 9 bytes, but can be larger.
        // We need to copy any extra data between the standard header and the first tag.
        let remainingHeaderSize = Int(headerSize) - 9
        if remainingHeaderSize > 0 {
            writer.write(try reader.readBytes(count: remainingHeaderSize))
        }
        
        // Write PreviousTagSize0
        writer.write(try reader.readBytes(count: 4))

        var metadataTagFound = false

        // 2. Iterate through tags, replacing metadata tag
        while !reader.isAtEnd {
            guard reader.remainingBytes >= 11 else { break }
            
            let tagHeaderOffset = reader.offset
            let tagHeaderData = try reader.peekBytes(count: 11)
            let tagType = tagHeaderData[0]
            let dataSize = UInt32(tagHeaderData[1]) << 16 | UInt32(tagHeaderData[2]) << 8 | UInt32(tagHeaderData[3])

            if tagType == 18 { // Script Data Tag
                // Temporarily parse to see if it's the onMetaData tag
                let tempReader = DataReader(data: try reader.peekBytes(count: 11 + Int(dataSize)))
                try tempReader.advance(by: 11) // Skip header
                let scriptData = try tempReader.readBytes(count: Int(dataSize))
                let scriptDetails = ScriptDetails(data: scriptData)

                if scriptDetails.name == "onMetaData" {
                    metadataTagFound = true
                    
                    // It's the metadata tag, so we generate a new one and write it.
                    let newScriptData = createMetadataScriptData(metadata: newMetadata)
                    let newScriptDataSize = UInt32(newScriptData.count)
                    
                    // Write new header
                    writer.write(18) // Tag Type
                    writer.writeUInt24(newScriptDataSize)
                    writer.writeUInt32(0) // Timestamp is 0 for metadata
                    writer.writeUInt24(0) // StreamID is 0
                    
                    // Write new data
                    writer.write(newScriptData)
                    
                    // Write new PreviousTagSize
                    writer.writeUInt32(11 + newScriptDataSize)
                    
                    // Advance the reader past the old tag in the original data
                    try reader.advance(by: 11 + Int(dataSize) + 4)
                    continue // Continue to the next tag
                }
            }
            
            // If it's not the metadata tag, copy it verbatim
            let fullTagSize = 11 + Int(dataSize) + 4
            guard reader.remainingBytes >= fullTagSize else { break }
            writer.write(try reader.readBytes(count: fullTagSize))
        }

        // If no metadata tag was found to replace, we can't save.
        guard metadataTagFound else {
            throw ParserError.metadataNotFound
        }

        return writer.data
    }
    
    private func createMetadataScriptData(metadata: [String: Any]) -> Data {
        let writer = DataWriter()
        // AMF1: String "onMetaData"
        writer.write(2)
        writer.writeAMFString("onMetaData")
        // AMF2: ECMA Array (the metadata object)
        writer.writeAMFObject(metadata)
        return writer.data
    }
    
    func repairFLV(url: URL) throws -> Data {
        let originalData = try Data(contentsOf: url)
        let repairReader = DataReader(data: originalData)
        let writer = DataWriter()

        guard originalData.count >= 13 else { throw ParserError.dataTooShort }
        writer.write(try repairReader.readBytes(count: 13))

        while !repairReader.isAtEnd {
            guard repairReader.remainingBytes >= 11 else { break }
            
            let headerData = try repairReader.peekBytes(count: 11)
            let dataSize = Int(UInt32(headerData[1]) << 16 | UInt32(headerData[2]) << 8 | UInt32(headerData[3]))
            
            let fullTagSize = 11 + dataSize + 4
            guard repairReader.remainingBytes >= fullTagSize else { break }
            
            writer.write(try repairReader.readBytes(count: fullTagSize))
        }
        return writer.data
    }
}


// MARK: - Model Extensions for Parsing

extension FLVTag {
    init(offset: Int, headerData: Data, tagData: Data, globalMetadata: [String: Any]) {
        self.offset = offset
        
        let typeRaw = headerData[0]
        self.dataSize = UInt32(headerData[1]) << 16 | UInt32(headerData[2]) << 8 | UInt32(headerData[3])
        self.timestamp = UInt32(headerData[4]) << 16 | UInt32(headerData[5]) << 8 | UInt32(headerData[6]) | (UInt32(headerData[7]) << 24)
        self.streamId = UInt32(headerData[8]) << 16 | UInt32(headerData[9]) << 8 | UInt32(headerData[10])
        
        switch typeRaw {
        case 8:
            self.type = .audio
            self.details = .audio(AudioDetails(data: tagData, globalMetadata: globalMetadata))
        case 9:
            self.type = .video
            self.details = .video(VideoDetails(data: tagData))
        case 18:
            self.type = .script
            self.details = .script(ScriptDetails(data: tagData))
        default:
            self.type = .unknown
            self.details = .unknown
        }
    }
}

extension AudioDetails {
    init(data: Data, globalMetadata: [String: Any]) {
        guard !data.isEmpty else {
            self = .init(format: "Empty", sampleRate: "", sampleSize: "", channels: "", aacPacketType: nil, audioObjectType: nil)
            return
        }
        
        let flags = data[0]
        let soundFormat = (flags >> 4) & 0x0F
        
        self.format = Constants.AUDIO_FORMATS[soundFormat] ?? "Unknown (\(soundFormat))"
        self.sampleSize = Constants.AUDIO_BITS[(flags >> 1) & 0x01] ?? "Unknown"
        
        var finalSampleRate: String?
        var finalChannels: String?
        
        if soundFormat == 10 && data.count > 1 { // AAC
            let aacPacketTypeRaw = data[1]
            self.aacPacketType = aacPacketTypeRaw == 0 ? "AAC sequence header" : "AAC raw"
            
            if aacPacketTypeRaw == 0 && data.count > 3 { // Sequence Header
                let reader = BitReader(data: data.subdata(in: 2..<data.count))
                let objType = reader.read(bits: 5)
                let freqIdx = reader.read(bits: 4)
                let chanCfg = reader.read(bits: 4)
                
                self.audioObjectType = Constants.AAC_AUDIO_OBJECT_TYPES[objType]
                finalSampleRate = Constants.AAC_SAMPLING_FREQUENCIES[freqIdx]
                finalChannels = Constants.AAC_CHANNEL_CONFIGURATIONS[chanCfg]
            } else {
                 self.audioObjectType = nil
            }
        } else {
            self.aacPacketType = nil
            self.audioObjectType = nil
        }
        
        if let rate = finalSampleRate {
            self.sampleRate = rate
        } else if let metaRate = globalMetadata["audiosamplerate"] as? Double {
            self.sampleRate = "\(Int(metaRate)) Hz"
        } else {
            self.sampleRate = Constants.AUDIO_RATES[(flags >> 2) & 0x03] ?? "Unknown"
        }
        
        if let chans = finalChannels {
            self.channels = chans
        } else if let isStereo = globalMetadata["stereo"] as? Bool {
            self.channels = isStereo ? "Stereo" : "Mono"
        } else {
            self.channels = Constants.AUDIO_CHANNELS[flags & 0x01] ?? "Unknown"
        }
    }
}

extension VideoDetails {
    init(data: Data) {
        guard !data.isEmpty else {
            self = .init(frameType: "Empty", codec: "", avcPacketType: nil, compositionTimeOffset: nil)
            return
        }
        
        let flags = data[0]
        let frameTypeRaw = (flags >> 4) & 0x0F
        let codecID = flags & 0x0F
        
        self.frameType = Constants.VIDEO_FRAME_TYPES[frameTypeRaw] ?? "Unknown (\(frameTypeRaw))"
        self.codec = Constants.VIDEO_CODECS[codecID] ?? "Unknown (\(codecID))"
        
        if codecID == 7 && data.count > 4 { // AVC
            let avcPacketTypeRaw = data[1]
            self.avcPacketType = ["AVC sequence header", "AVC NALU", "AVC end of sequence"][Int(avcPacketTypeRaw)]
            
            let ctsByte2 = Int32(data[2]) << 16
            let ctsByte3 = Int32(data[3]) << 8
            let ctsByte4 = Int32(data[4])
            // Combine to form a 24-bit signed integer
            let compositionTime = (ctsByte2 | ctsByte3 | ctsByte4)
            self.compositionTimeOffset = (compositionTime & 0x800000) != 0 ? (compositionTime | ~0xFFFFFF) : compositionTime
        } else {
            self.avcPacketType = nil
            self.compositionTimeOffset = nil
        }
    }
}

extension ScriptDetails {
    init(data: Data) {
        var reader = DataReader(data: data)
        
        // Use an immediately-executing closure to handle the do-catch logic
        // and return a tuple, which is a cleaner way to initialize constants.
        let (parsedName, parsedValue): (String, Any) = {
            do {
                let name = try reader.parseAMFValue() as? String ?? "N/A"
                let value = try reader.parseAMFValue()
                return (name, value)
            } catch {
                return ("Parse Error", "Could not parse script data.")
            }
        }()
        
        self.name = parsedName
        self.value = parsedValue
    }
}

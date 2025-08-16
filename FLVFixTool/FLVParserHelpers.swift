//
//  FLVParserHelpers.swift
//  FLVFixTool
//
//  Created by Gemini on 2025/8/16.
//

import Foundation

// MARK: - Constants
// Replicates the constant dictionaries from the Python script for easy lookup.
struct Constants {
    static let AUDIO_FORMATS: [UInt8: String] = [
        0: "Linear PCM, platform endian", 1: "ADPCM", 2: "MP3", 3: "Linear PCM, little endian",
        4: "Nellymoser 16kHz mono", 5: "Nellymoser 8kHz mono", 6: "Nellymoser",
        7: "G.711 A-law logarithmic PCM", 8: "G.711 mu-law logarithmic PCM", 9: "reserved",
        10: "AAC", 11: "Speex", 14: "MP3 8-Khz", 15: "Device-specific sound"
    ]
    static let AUDIO_RATES: [UInt8: String] = [0: "5.5 kHz", 1: "11 kHz", 2: "22 kHz", 3: "44 kHz"]
    static let AUDIO_BITS: [UInt8: String] = [0: "8-bit samples", 1: "16-bit samples"]
    static let AUDIO_CHANNELS: [UInt8: String] = [0: "Mono", 1: "Stereo"]
    
    static let VIDEO_FRAME_TYPES: [UInt8: String] = [
        1: "Key frame (for AVC, a seekable frame)", 2: "Inter frame (for AVC, a non-seekable frame)",
        3: "Disposable inter frame (H.263 only)", 4: "Generated key frame (reserved for server use only)",
        5: "Video info/command frame"
    ]
    static let VIDEO_CODECS: [UInt8: String] = [
        2: "Sorenson H.263", 3: "Screen video", 4: "On2 VP6",
        5: "On2 VP6 with alpha channel", 6: "Screen video version 2", 7: "AVC (H.264)"
    ]
    
    static let AAC_AUDIO_OBJECT_TYPES: [UInt8: String] = [
        1: "AAC Main", 2: "AAC LC (Low Complexity)", 3: "AAC SSR (Scalable Sample Rate)",
        4: "AAC LTP (Long Term Prediction)"
    ]
    static let AAC_SAMPLING_FREQUENCIES: [UInt8: String] = [
        0: "96000 Hz", 1: "88200 Hz", 2: "64000 Hz", 3: "48000 Hz", 4: "44100 Hz",
        5: "32000 Hz", 6: "24000 Hz", 7: "22050 Hz", 8: "16000 Hz", 9: "12000 Hz",
        10: "11025 Hz", 11: "8000 Hz", 12: "7350 Hz"
    ]
    static let AAC_CHANNEL_CONFIGURATIONS: [UInt8: String] = [
        1: "1 channel: Center front", 2: "2 channels: Left, Right", 3: "3 channels: Center, Left, Right",
        4: "4 channels: Center, Left, Right, Back", 5: "5 channels: Center, Left, Right, Back Left, Back Right",
        6: "6 channels (5.1): Center, L, R, BL, BR, LFE", 7: "8 channels (7.1): C, L, R, BL, BR, SL, SR, LFE"
    ]
}


// MARK: - Binary Data Helpers

/// Reads binary data sequentially from a Data object.
class DataReader {
    let data: Data
    private(set) var offset: Int = 0
    
    var remainingBytes: Int { data.count - offset }
    var isAtEnd: Bool { offset >= data.count }

    init(data: Data) {
        self.data = data
    }

    func seek(to newOffset: Int) {
        offset = max(0, min(data.count, newOffset))
    }
    
    func advance(by count: Int) {
        offset += count
    }

    func readBytes(count: Int) throws -> Data {
        guard remainingBytes >= count else { throw FLVParser.ParserError.dataTooShort }
        let subdata = data.subdata(in: offset..<(offset + count))
        offset += count
        return subdata
    }
    
    func peekBytes(count: Int) throws -> Data {
        guard remainingBytes >= count else { throw FLVParser.ParserError.dataTooShort }
        return data.subdata(in: offset..<(offset + count))
    }

    func readUInt8() throws -> UInt8 {
        return try readBytes(count: 1)[0]
    }

    func readUInt16() throws -> UInt16 {
        let bytes = try readBytes(count: 2)
        return UInt16(bigEndian: bytes.withUnsafeBytes { $0.load(as: UInt16.self) })
    }
    
    func readUInt24() throws -> UInt32 {
        let bytes = try readBytes(count: 3)
        return UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])
    }

    func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return UInt32(bigEndian: bytes.withUnsafeBytes { $0.load(as: UInt32.self) })
    }

    func readDouble() throws -> Double {
        let bytes = try readBytes(count: 8)
        return Double(bitPattern: UInt64(bigEndian: bytes.withUnsafeBytes { $0.load(as: UInt64.self) }))
    }

    func readString(length: Int) throws -> String {
        let bytes = try readBytes(count: length)
        return String(data: bytes, encoding: .utf8) ?? ""
    }
    
    // MARK: - AMF0 Parsing
    
    func parseAMFValue() throws -> Any {
        let typeMarker = try readUInt8()
        switch typeMarker {
        case 0: return try readDouble()
        case 1: return try readUInt8() != 0
        case 2:
            let length = try readUInt16()
            return try readString(length: Int(length))
        case 8: // ECMA Array
            let count = try readUInt32()
            var dict = [String: Any]()
            for _ in 0..<count {
                let keyLength = try readUInt16()
                let key = try readString(length: Int(keyLength))
                let value = try parseAMFValue()
                dict[key] = value
            }
            // Skip 3-byte terminator (0x00, 0x00, 0x09)
            try advance(by: 3)
            return dict
        default:
            return "Unsupported AMF Type: \(typeMarker)"
        }
    }
}

/// Writes binary data sequentially.
class DataWriter {
    private(set) var data = Data()
    
    func write(_ newData: Data) { data.append(newData) }
    func write(_ byte: UInt8) { data.append(byte) }

    func writeUInt16(_ value: UInt16) {
        var bigEndianValue = value.bigEndian
        data.append(Data(bytes: &bigEndianValue, count: MemoryLayout<UInt16>.size))
    }
    
    func writeUInt24(_ value: UInt32) {
        write(UInt8((value >> 16) & 0xFF))
        write(UInt8((value >> 8) & 0xFF))
        write(UInt8(value & 0xFF))
    }

    func writeUInt32(_ value: UInt32) {
        var bigEndianValue = value.bigEndian
        data.append(Data(bytes: &bigEndianValue, count: MemoryLayout<UInt32>.size))
    }

    func writeDouble(_ value: Double) {
        var bigEndianValue = value.bitPattern.bigEndian
        data.append(Data(bytes: &bigEndianValue, count: MemoryLayout<UInt64>.size))
    }

    func writeString(_ value: String) {
        if let stringData = value.data(using: .utf8) {
            data.append(stringData)
        }
    }
    
    // MARK: - AMF0 Writing
    
    func writeAMFString(_ value: String) {
        writeUInt16(UInt16(value.utf8.count))
        writeString(value)
    }
    
    func writeAMFObject(_ dictionary: [String: Any]) {
        write(8) // AMF ECMA Array marker
        writeUInt32(UInt32(dictionary.count))
        for (key, value) in dictionary {
            writeAMFString(key)
            writeAMFValue(value)
        }
        // End of object marker
        write(0)
        write(0)
        write(9)
    }
    
    func writeAMFValue(_ value: Any) {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            write(1) // AMF Boolean marker
            write(number.boolValue ? 1 : 0)
        } else if let number = value as? Double {
            write(0) // AMF Number marker
            writeDouble(number)
        } else if let number = value as? Int {
            write(0) // AMF Number marker
            writeDouble(Double(number))
        } else if let string = value as? String {
            write(2) // AMF String marker
            writeAMFString(string)
        } else if let dict = value as? [String: Any] {
            writeAMFObject(dict)
        }
        // Note: Other AMF types are not handled in this simplified implementation.
    }
}

/// Reads bits sequentially from a Data object for parsing AAC headers.
class BitReader {
    private let data: Data
    private var bytePosition: Int = 0
    private var bitPosition: Int = 0

    init(data: Data) {
        self.data = data
    }

    func read(bits count: Int) -> UInt8 {
        var returnValue: UInt8 = 0
        for _ in 0..<count {
            returnValue <<= 1
            if (data[bytePosition] & (0x80 >> bitPosition)) != 0 {
                returnValue |= 1
            }
            bitPosition += 1
            if bitPosition == 8 {
                bitPosition = 0
                bytePosition += 1
            }
        }
        return returnValue
    }
}

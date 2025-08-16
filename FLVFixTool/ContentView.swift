import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Content View
struct ContentView: View {
    @State private var flvFile: FLVFile?
    @State private var errorMessage: String?
    
    @State private var isFileImporterPresented = false
    @State private var isDropTargeted = false
    @State private var fileDataToSave: Data?
    @State private var isSaveExporterPresented = false
    @State private var defaultSaveName = ""
    
    // State for the editable metadata
    @State private var metadataItems: [MetaDataItem] = []
    
    // Navigation state
    @State private var selection: Panel? = .header
    @State private var tagSelection: FLVTag.ID?

    enum Panel: Hashable {
        case header, metadata, tags
    }

    var body: some View {
        NavigationSplitView {
            // --- Sidebar ---
            List(selection: $selection) {
                Label("Header", systemImage: "doc.text").tag(Panel.header)
                Label("Metadata", systemImage: "tablecells").tag(Panel.metadata)
                Label("Tags", systemImage: "tag.stack").tag(Panel.tags)
            }
            .navigationSplitViewColumnWidth(180)
            .disabled(flvFile == nil)
            
        } content: {
            // --- Content List (Middle Column) ---
            if let flvFile = flvFile {
                switch selection {
                case .header:
                    HeaderDetailView(header: flvFile.header)
                case .metadata:
                    MetadataEditorView(items: $metadataItems)
                case .tags:
                    TagListView(tags: flvFile.tags, selection: $tagSelection)
                case .none:
                    Text("Select an item")
                }
            } else {
                placeholderView
            }
        } detail: {
            // --- Detail View (Right Column) ---
            if let flvFile = flvFile, let tagID = tagSelection, let tag = flvFile.tags.first(where: { $0.id == tagID }) {
                TagDetailView(tag: tag)
            } else {
                Text("Select a tag to see details")
            }
        }
        .navigationTitle(flvFile?.fileName ?? "FLVFixTool")
        .toolbar { toolbarContent }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.flv], onCompletion: handleFileSelection)
        .fileExporter(isPresented: $isSaveExporterPresented, document: FLVDocument(data: fileDataToSave ?? Data()), contentType: .flv, defaultFilename: defaultSaveName) { result in
            if case .failure(let error) = result {
                errorMessage = "Failed to save file: \(error.localizedDescription)"
            }
        }
        .onChange(of: flvFile?.sourceURL) { // Observe the URL, which is Equatable
            updateMetadataItems(from: flvFile?.metadata)
        }
        .onOpenURL { url in
            parseFile(at: url)
        }
    }

    // MARK: - Subviews & View Logic
    
    @ViewBuilder
    private var placeholderView: some View {
        VStack {
            ContentUnavailableView {
                Label("No FLV File Loaded", systemImage: "film.stack")
            } description: {
                Text("Select a file or drop one here.")
            }
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(8)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: { isFileImporterPresented = true }) {
                HStack {
                    Image(systemName: "doc")
                    Text("Open")
                }
            }
            
            Button(action: repairFile) {
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                    Text("Repair")
                }
            }
            .disabled(flvFile == nil)
            
            Button(action: saveFile) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save")
                }
            }
            .disabled(flvFile == nil)
        }
    }

    // MARK: - Handlers
    
    private func repairFile() {
        guard let url = flvFile?.sourceURL, let fileName = flvFile?.fileName else { return }
        do {
            let parser = FLVParser()
            fileDataToSave = try parser.repairFLV(url: url)
            defaultSaveName = fileName.replacingOccurrences(of: ".flv", with: "_repaired.flv")
            isSaveExporterPresented = true
        } catch {
            errorMessage = "Failed to repair file: \(error.localizedDescription)"
        }
    }
    
    private func saveFile() {
        guard let url = flvFile?.sourceURL, let fileName = flvFile?.fileName else { return }
        do {
            let newMetadata = metadataItems.reduce(into: [String: Any]()) { (dict, item) in
                dict[item.key] = convertValue(item.value)
            }
            let parser = FLVParser()
            fileDataToSave = try parser.generateNewFLV(originalURL: url, newMetadata: newMetadata)
            defaultSaveName = fileName.replacingOccurrences(of: ".flv", with: "_edited.flv")
            isSaveExporterPresented = true
        } catch {
            errorMessage = "Failed to save file: \(error.localizedDescription)"
        }
    }
    
    /// Converts a string value from a TextField back to a more appropriate type (Double, Bool, String).
    private func convertValue(_ stringValue: String) -> Any {
        if let doubleValue = Double(stringValue) {
            return doubleValue
        }
        if stringValue.lowercased() == "true" {
            return true
        }
        if stringValue.lowercased() == "false" {
            return false
        }
        return stringValue
    }
    
    private func handleFileSelection(result: Result<URL, Error>) {
        if case .success(let url) = result {
            parseFile(at: url)
        } else if case .failure(let error) = result {
            errorMessage = "Failed to select file: \(error.localizedDescription)"
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { (item, error) in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                parseFile(at: url)
            }
        }
        return true
    }

    func parseFile(at url: URL) {
        do {
            let parser = FLVParser()
            let parsedFile = try parser.parse(url: url)
            self.flvFile = parsedFile
            self.errorMessage = nil
            self.selection = .header // Default to showing header
        } catch {
            self.errorMessage = "Failed to parse file: \(error.localizedDescription)"
            self.flvFile = nil
        }
    }
    
    private func updateMetadataItems(from metadata: [String: Any]?) {
        guard let metadata = metadata else { 
            metadataItems = []
            return
        }
        metadataItems = metadata.map { key, value in
            MetaDataItem(key: key, value: String(describing: value))
        }.sorted(by: { $0.key < $1.key })
    }
}

// MARK: - Child Views

struct HeaderDetailView: View {
    let header: FLVHeader
    var body: some View {
        Form {
            Section("Header Information") {
                LabeledContent("Signature", value: header.signature)
                LabeledContent("Version", value: "\(header.version)")
                LabeledContent("Has Audio", value: header.hasAudio ? "Yes" : "No")
                LabeledContent("Has Video", value: header.hasVideo ? "Yes" : "No")
                LabeledContent("Header Size", value: "\(header.headerSize) bytes")
            }
        }
        .padding()
        .textSelection(.enabled)
    }
}

struct MetadataEditorView: View {
    @Binding var items: [MetaDataItem]
    var body: some View {
        Form {
            Section("Metadata (Editable)") {
                if items.isEmpty {
                    Text("No metadata found in this file.")
                } else {
                    ForEach($items) { $item in
                        LabeledContent(item.key) { // Corrected: Pass the String value, not the binding
                            TextField("Value", text: $item.value)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
        }
        .padding()
        .textSelection(.enabled)
    }
}

struct TagListView: View {
    let tags: [FLVTag]
    @Binding var selection: FLVTag.ID?
    
    var body: some View {
        Table(tags, selection: $selection) {
            TableColumn("No.") { tag in Text("\(tags.firstIndex(where: { $0.id == tag.id })! + 1)") }.width(40)
            TableColumn("Type") { tag in
                HStack {
                    Image(systemName: tag.type == .video ? "video.fill" : (tag.type == .audio ? "speaker.wave.2.fill" : "doc.text.fill"))
                        .foregroundColor(tag.type == .video ? .blue : (tag.type == .audio ? .green : .orange))
                    Text(tag.type.rawValue)
                }
            }
            // Removed the `value:` parameter to fix the compiler error
            TableColumn("Timestamp (ms)") { tag in Text("\(tag.timestamp)") }
            TableColumn("Size (bytes)") { tag in Text("\(tag.dataSize)") }
            TableColumn("Analysis") { tag in
                if let analysis = tag.analysis {
                    Label(analysis, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                }
            }
        }
    }
}

struct TagDetailView: View {
    let tag: FLVTag
    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Offset", value: String(format: "0x%08X", tag.offset))
                LabeledContent("Timestamp", value: "\(tag.timestamp) ms")
                LabeledContent("Data Size", value: "\(tag.dataSize) bytes")
                LabeledContent("Stream ID", value: "\(tag.streamId)")
            }
            
            Section("Details") {
                switch tag.details {
                case .audio(let details): AudioDetailRows(details: details)
                case .video(let details): VideoDetailRows(details: details)
                case .script(let details): ScriptDetailRows(details: details)
                case .unknown: Text("No details for unknown tag type.")
                }
            }
        }
        .padding()
        .textSelection(.enabled)
        .navigationTitle("Tag at \(tag.timestamp) ms")
        .toolbar {
            ToolbarItem {
                Button {
                    copyTagDetailsToClipboard()
                } label: {
                    Label("Copy Details", systemImage: "doc.on.doc")
                }
            }
        }
    }
    
    private func copyTagDetailsToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(generateDetailsString(), forType: .string)
    }
    
    private func generateDetailsString() -> String {
        var components: [String] = []
        components.append("--- General ---")
        let formattedOffset = String(format: "0x%08X", tag.offset)
        components.append("Offset: \(formattedOffset)")
        components.append("Timestamp: \(tag.timestamp) ms")
        components.append("Data Size: \(tag.dataSize) bytes")
        components.append("Stream ID: \(tag.streamId)")
        components.append("")

        components.append("--- Details ---")
        switch tag.details {
        case .audio(let details):
            components.append(contentsOf: details.toStringArray())
        case .video(let details):
            components.append(contentsOf: details.toStringArray())
        case .script(let details):
            components.append(contentsOf: details.toStringArray())
        case .unknown:
            components.append("No details for unknown tag type.")
        }

        return components.joined(separator: "\n")
    }
}

struct AudioDetailRows: View {
    let details: AudioDetails
    var body: some View {

        LabeledContent("Format", value: details.format)
        LabeledContent("Sample Rate", value: details.sampleRate)
        LabeledContent("Sample Size", value: details.sampleSize)
        LabeledContent("Channels", value: details.channels)
        if let type = details.aacPacketType {
            LabeledContent("AAC Packet Type", value: type)
        }
        if let type = details.audioObjectType {
            LabeledContent("Audio Object Type", value: type)
        }
    }
}

struct VideoDetailRows: View {
    let details: VideoDetails
    var body: some View {
        LabeledContent("Frame Type", value: details.frameType)
        LabeledContent("Codec", value: details.codec)
        if let type = details.avcPacketType {
            LabeledContent("AVC Packet Type", value: type)
        }
        if let offset = details.compositionTimeOffset {
            LabeledContent("Composition Time Offset", value: "\(offset)")
        }
    }
}

struct ScriptDetailRows: View {
    let details: ScriptDetails
    var body: some View {
        LabeledContent("Name", value: details.name)
        // A simple description is better for the UI than trying to render a complex object.
        LabeledContent("Value", value: String(describing: details.value))
    }
}

// MARK: - Models & Helpers

struct MetaDataItem: Identifiable, Hashable {
    let id = UUID()
    var key: String
    var value: String
}

extension UTType {
    static var flv: UTType { UTType(importedAs: "com.adobe.flash-video") }
}

struct FLVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.flv] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

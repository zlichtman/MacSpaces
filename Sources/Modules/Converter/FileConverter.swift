import AppKit
import Darwin
import AVFoundation
import ImageIO
import PDFKit
import Quartz
import UniformTypeIdentifiers

/// Converts and processes files on this Mac with system frameworks only
/// (ImageIO, PDFKit, AVFoundation, Foundation's document readers, ditto/zip).
/// Results are saved beside the originals, which are never changed.
enum FileConverter {
    enum Family: Equatable { case image, pdf, video, audio, document, archive, other }

    /// One choice on the wheel: a target format (convert) or a tool.
    struct Action: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let symbol: String?
        var options: Options? = nil
    }
    struct Options: Hashable, Sendable, Codable {
        var maximumBytes: Int64 = 5_000_000
        var maximumDimension: Int = 1600
        var cropRatio: Double = 0
        var quality: Double = 0.85
        var gifStart: Double = 0
        var gifDuration: Double = 8
        var gifFPS: Double = 12
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func family(of url: URL) -> Family {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .zip) { return .archive }
        let documents: [UTType] = [.plainText, .rtf, .rtfd, .html, .flatRTFD]
            + ["org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc",
               "org.oasis-open.opendocument.text", "com.apple.webarchive"].compactMap(UTType.init)
        if documents.contains(where: type.conforms(to:)) { return .document }
        return .other
    }

    // MARK: Catalog

    /// Image formats this Mac can write, in the order the wheel shows them.
    private static let imageTargets: [(id: String, title: String, type: UTType)] = {
        let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        let candidates: [(String, String, UTType?)] = [
            ("jpg", "JPG", .jpeg), ("png", "PNG", .png), ("heic", "HEIC", .heic), ("webp", "WEBP", .webP),
            ("tiff", "TIFF", .tiff), ("gif", "GIF", .gif), ("bmp", "BMP", .bmp), ("avif", "AVIF", UTType("public.avif")),
        ]
        return candidates.compactMap { id, title, type in
            guard let type, writable.contains(type.identifier) else { return nil }
            return (id, title, type)
        }
    }()

    /// What the wheel offers for these files: formats, or with `tools` the
    /// tools for their kind. Mixed selections get what every file supports.
    static func actions(for urls: [URL], tools: Bool) -> [Action] {
        let families = Set(urls.map(family(of:)))
        guard families.count == 1, let family = families.first else {
            return [Action(id: "zip", title: "ZIP", symbol: "doc.zipper")]
        }
        let ownExtension = urls.count == 1 ? urls[0].pathExtension.lowercased() : ""
        if tools {
            if family == .image, urls.contains(where: isMultiFrame) {
                return [Action(id: "tool.firstframe", title: "First frame", symbol: "photo"),
                        Action(id: "tool.ocr", title: "Copy Text", symbol: "text.viewfinder"),
                        Action(id: "zip", title: "ZIP", symbol: "doc.zipper")]
            }
            switch family {
            case .image:
                // Combining into one PDF only makes sense for several images.
                return [Action(id: "tool.compress", title: "Compress", symbol: "arrow.down.right.and.arrow.up.left"),
                        Action(id: "tool.strip", title: "Metadata", symbol: "eye.slash"),
                        Action(id: "tool.half", title: "Half size", symbol: "square.resize.down"),
                        Action(id: "tool.under1mb", title: "Under 1 MB", symbol: "arrow.down.to.line")]
                    + (urls.count > 1 ? [Action(id: "tool.pdf", title: "One PDF", symbol: "doc.richtext")] : [])
                    + [Action(id: "tool.ocr", title: "Copy Text", symbol: "text.viewfinder"),
                       Action(id: "tool.cutout", title: "Cutout", symbol: "person.crop.rectangle"),
                       Action(id: "zip", title: "ZIP", symbol: "doc.zipper")]
            case .pdf:
                // Split needs more than one page; merge needs more than one file.
                let pages = urls.count == 1 ? (PDFDocument(url: urls[0])?.pageCount ?? 0) : 0
                return [Action(id: "tool.compress", title: "Compress", symbol: "arrow.down.right.and.arrow.up.left")]
                    + (pages > 1 ? [Action(id: "tool.split", title: "Split pages", symbol: "square.split.2x1")] : [])
                    + (urls.count > 1 ? [Action(id: "tool.merge", title: "Merge", symbol: "square.stack")] : [])
                    + [Action(id: "tool.strip", title: "Metadata", symbol: "eye.slash"),
                       Action(id: "tool.ocr", title: "Copy Text", symbol: "text.viewfinder"),
                       Action(id: "zip", title: "ZIP", symbol: "doc.zipper")]
            case .video:
                return [Action(id: "tool.compress", title: "Compress", symbol: "arrow.down.right.and.arrow.up.left"),
                        Action(id: "tool.audio", title: "Audio", symbol: "waveform"),
                        Action(id: "tool.gif", title: "GIF", symbol: "photo.stack"),
                        Action(id: "tool.snapshot", title: "Snapshot", symbol: "camera"),
                        Action(id: "zip", title: "ZIP", symbol: "doc.zipper")]
            case .audio:
                return [Action(id: "tool.compress", title: "Compress", symbol: "arrow.down.right.and.arrow.up.left"),
                        Action(id: "zip", title: "ZIP", symbol: "doc.zipper")]
            case .archive:
                return [Action(id: "tool.unzip", title: "Unzip", symbol: "archivebox")]
            case .document, .other:
                return [Action(id: "zip", title: "ZIP", symbol: "doc.zipper")]
            }
        }
        let formats: [Action]
        switch family {
        case .image:
            formats = imageTargets.map { Action(id: "image.\($0.id)", title: $0.title, symbol: nil) }
                + [Action(id: "image.pdf", title: "PDF", symbol: nil)]
        case .pdf:
            formats = [Action(id: "pdf.png", title: "PNG", symbol: nil), Action(id: "pdf.jpg", title: "JPG", symbol: nil)]
        case .video:
            formats = [Action(id: "video.mp4", title: "MP4", symbol: nil), Action(id: "video.mov", title: "MOV", symbol: nil),
                       Action(id: "video.m4v", title: "M4V", symbol: nil), Action(id: "video.gif", title: "GIF", symbol: nil),
                       Action(id: "video.m4a", title: "M4A", symbol: nil)]
        case .audio:
            formats = [Action(id: "audio.m4a", title: "M4A", symbol: nil), Action(id: "audio.wav", title: "WAV", symbol: nil),
                       Action(id: "audio.aiff", title: "AIFF", symbol: nil), Action(id: "audio.caf", title: "CAF", symbol: nil)]
        case .document:
            formats = [Action(id: "doc.pdf", title: "PDF", symbol: nil), Action(id: "doc.docx", title: "DOCX", symbol: nil),
                       Action(id: "doc.rtf", title: "RTF", symbol: nil), Action(id: "doc.txt", title: "TXT", symbol: nil),
                       Action(id: "doc.html", title: "HTML", symbol: nil), Action(id: "doc.odt", title: "ODT", symbol: nil)]
        case .archive:
            formats = [Action(id: "tool.unzip", title: "Unzip", symbol: "archivebox")]
        case .other:
            formats = [Action(id: "zip", title: "ZIP", symbol: "doc.zipper")]
        }
        // Never offer the format a single file already has.
        let filtered = formats.filter { action in
            let target = action.id.split(separator: ".").last.map(String.init) ?? ""
            return !(target == ownExtension || (target == "jpg" && ownExtension == "jpeg") || (target == "tiff" && ownExtension == "tif"))
        }
        return Array(filtered.prefix(8))
    }

    /// One transaction per input: outputs stay hidden until the action succeeds.
    /// Reserved destinations prevent concurrent jobs from replacing each other.
    private final class Transaction: @unchecked Sendable {
        private var paths: [(staging: URL, final: URL)] = []

        func allocate(_ final: URL, directory: Bool) throws -> URL {
            if directory {
                try FileManager.default.createDirectory(at: final, withIntermediateDirectories: false)
            } else {
                let descriptor = Darwin.open(final.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
                guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                Darwin.close(descriptor)
            }
            let staging = final.deletingLastPathComponent().appendingPathComponent(".macspaces-" + UUID().uuidString + "-" + final.lastPathComponent)
            paths.append((staging, final))
            return staging
        }

        func commit(_ outputs: [URL]) throws -> [URL] {
            try Task.checkCancellation()
            for pair in paths {
                guard Darwin.rename(pair.staging.path, pair.final.path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
            let result = outputs.map { output in paths.first { $0.staging.standardizedFileURL.path == output.standardizedFileURL.path }?.final ?? output }
            paths.removeAll()
            return result
        }

        func discard(_ staging: URL) {
            if let index = paths.firstIndex(where: { $0.staging.standardizedFileURL.path == staging.standardizedFileURL.path }) {
                let pair = paths.remove(at: index)
                try? FileManager.default.removeItem(at: pair.staging)
                try? FileManager.default.removeItem(at: pair.final)
            }
        }

        func rollback() {
            for pair in paths {
                try? FileManager.default.removeItem(at: pair.staging)
                try? FileManager.default.removeItem(at: pair.final)
            }
            paths.removeAll()
        }
    }
    @TaskLocal private static var transaction: Transaction?
    @TaskLocal private static var reportProgress: (@Sendable (Double) async -> Void)?

    struct BatchResult: Sendable {
        struct Issue: Sendable { let url: URL; let message: String }
        var outputs: [URL] = []
        var issues: [Issue] = []
        var cancelled = false
        var remaining: [URL] = []
    }

    /// Keeps completed results even if another input is unreadable or cancelled.
    static func runBatch(_ action: Action, on urls: [URL],
                         progress: @escaping @MainActor @Sendable (Double) -> Void) async -> BatchResult {
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        var result = BatchResult()
        if let options = action.options,
           !((10_000...2_000_000_000).contains(options.maximumBytes) && (1...16000).contains(options.maximumDimension)
             && options.cropRatio.isFinite && options.cropRatio >= 0 && options.cropRatio <= 100
             && options.quality.isFinite && (0...1).contains(options.quality)
             && options.gifStart.isFinite && options.gifStart >= 0
             && options.gifDuration.isFinite && options.gifDuration > 0
             && options.gifFPS.isFinite && options.gifFPS > 0) {
            result.issues = urls.map { .init(url: $0, message: "Use positive file limits and finite image or GIF settings.") }
            return result
        }
        let combined = ["zip", "tool.pdf", "tool.merge"].contains(action.id)
        let groups = combined ? [urls] : urls.map { [$0] }
        for (index, group) in groups.enumerated() {
            guard let input = group.first else { continue }
            if Task.isCancelled { result.cancelled = true; result.remaining = groups[index...].flatMap { $0 }; break }
            let tx = Transaction()
            do {
                let written = try await $transaction.withValue(tx) {
                    try await $reportProgress.withValue({ fraction in
                        await progress((Double(index) + fraction) / Double(max(groups.count, 1)))
                    }) {
                        try Task.checkCancellation()
                        let outputs: [URL]
                        switch action.id {
                        case "zip": outputs = [try zip(group)]
                        case "tool.pdf": outputs = [try imagesToPDF(group)]
                        case "tool.merge": outputs = [try mergePDFs(group)]
                        default: outputs = try await runOne(action, on: input)
                        }
                        return try tx.commit(outputs)
                    }
                }
                result.outputs += written
            } catch {
                tx.rollback()
                if Task.isCancelled || error is CancellationError { result.cancelled = true; result.remaining = groups[index...].flatMap { $0 }; break }
                result.issues += group.map { BatchResult.Issue(url: $0, message: error.localizedDescription) }
            }
            await progress(Double(index + 1) / Double(max(groups.count, 1)))
        }
        return result
    }

    static func isMultiFrame(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    static func presets(for urls: [URL]) -> [Action] {
        guard let first = urls.first, urls.allSatisfy({ family(of: $0) == family(of: first) }) else { return [] }
        switch family(of: first) {
        case .image where !urls.contains(where: isMultiFrame):
            return [Action(id: "preset.email", title: "Email ready · under 1 MB", symbol: "envelope"),
                    Action(id: "preset.size", title: "Target file size…", symbol: "arrow.down.to.line"),
                    Action(id: "preset.resize", title: "Resize or crop…", symbol: "crop")]
        case .video:
            return [Action(id: "preset.size", title: "Target file size…", symbol: "arrow.down.to.line"),
                    Action(id: "preset.gif", title: "GIF clip…", symbol: "photo.stack")]
        default: return []
        }
    }

    // MARK: Running

    /// Runs one action on every file and returns the files it wrote.
    static func run(_ action: Action, on urls: [URL], progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> [URL] {
        let result = await runBatch(action, on: urls, progress: progress)
        if result.cancelled { throw CancellationError() }
        if let issue = result.issues.first { throw Failure(message: issue.message) }
        return result.outputs
    }

    private static func runOne(_ action: Action, on url: URL) async throws -> [URL] {
        let parts = action.id.split(separator: ".").map(String.init)
        guard parts.count == 2 else { throw Failure(message: "Unknown action") }
        switch (parts[0], parts[1]) {
        case ("image", "pdf"):
            guard !isMultiFrame(url) else { throw Failure(message: "Use First frame before making a PDF from this multi-frame image.") }
            return [try imagesToPDF([url])]
        case ("image", let target):
            guard let type = imageTargets.first(where: { $0.id == target })?.type else { throw Failure(message: "\(target.uppercased()) isn't supported") }
            let out = try destination(for: url, ext: target)
            try writeImage(url, to: out, type: type)
            return [out]
        case ("pdf", let target): return try pdfToImages(url, type: target == "png" ? .png : .jpeg, ext: target)
        case ("video", "gif"): return [try await videoToGIF(url)]
        case ("video", "m4a"), ("tool", "audio") where family(of: url) == .video:
            return [try await export(url, preset: AVAssetExportPresetAppleM4A, type: .m4a, ext: "m4a")]
        case ("video", let target):
            let type: AVFileType = target == "mov" ? .mov : target == "m4v" ? .m4v : .mp4
            return [try await export(url, preset: AVAssetExportPresetHighestQuality, type: type, ext: target)]
        case ("audio", "m4a"): return [try await export(url, preset: AVAssetExportPresetAppleM4A, type: .m4a, ext: "m4a")]
        case ("audio", let target): return [try writePCM(url, ext: target)]
        case ("doc", let target): return [try await convertDocument(url, ext: target)]
        case ("preset", "email"): return [try underOneMegabyte(url)]
        case ("preset", "size"): return [try await targetSize(url, options: action.options ?? Options())]
        case ("preset", "resize"):
            let options = action.options ?? Options()
            let out = try destination(for: url, ext: "png", suffix: "resized")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { throw Failure(message: "Can't read this image") }
            let largest = max(properties[kCGImagePropertyPixelWidth] as? Double ?? 1, properties[kCGImagePropertyPixelHeight] as? Double ?? 1)
            try writeImage(url, to: out, type: .png, scale: min(1, Double(max(1, options.maximumDimension)) / largest), cropRatio: options.cropRatio)
            return [out]
        case ("preset", "gif"): return [try await videoToGIF(url, options: action.options ?? Options())]
        case ("tool", "firstframe"):
            let out = try destination(for: url, ext: "png", suffix: "first frame")
            try writeImage(url, to: out, type: .png, firstFrame: true)
            return [out]
        case ("tool", "ocr"), ("tool", "cutout"):
            let operation: LocalFileTools.Operation = parts[1] == "ocr" ? .extractText : .removeBackground
            if operation == .removeBackground, isMultiFrame(url) { throw Failure(message: "Use First frame before making a cutout from a multi-frame image.") }
            let data = try await LocalFileTools.process(url, operation: operation)
            try Task.checkCancellation()
            let out = try destination(for: url, ext: operation.suffix, suffix: parts[1] == "ocr" ? "text" : "cutout")
            try data.write(to: out, options: .atomic)
            return [out]
        case ("tool", "unzip"): return [try unzip(url)]
        case ("tool", "snapshot"): return [try await snapshot(url)]
        case ("tool", "gif"): return [try await videoToGIF(url)]
        case ("tool", "split"): return try splitPDF(url)
        case ("tool", "compress"): return [try await compress(url)]
        case ("tool", "strip"): return [try stripMetadata(url)]
        case ("tool", "under1mb"):
            return [try underOneMegabyte(url)]
        case ("tool", "half"):
            let ext = url.pathExtension.lowercased()
            let type = UTType(filenameExtension: ext) ?? .png
            let out = try destination(for: url, ext: ext, suffix: "half size")
            try writeImage(url, to: out, type: type, scale: 0.5)
            return [out]
        default: throw Failure(message: "\(action.title) isn't available for \(url.lastPathComponent)")
        }
    }

    // MARK: Destinations

    /// Beside the original (or in Downloads when that folder is read-only),
    /// never replacing an existing file.
    static func destination(for url: URL, ext: String, suffix: String? = nil) throws -> URL {
        var folder = url.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: folder.path) {
            folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        let base = url.deletingPathExtension().lastPathComponent + (suffix.map { " (\($0))" } ?? "")
        var candidate = ext.isEmpty ? folder.appendingPathComponent(base) : folder.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = ext.isEmpty ? folder.appendingPathComponent("\(base) \(counter)") : folder.appendingPathComponent("\(base) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        guard let transaction else { return candidate }
        while true {
            do { return try transaction.allocate(candidate, directory: ext.isEmpty) }
            catch let error as POSIXError where error.code == .EEXIST {
                candidate = ext.isEmpty ? folder.appendingPathComponent("\(base) \(counter)") : folder.appendingPathComponent("\(base) \(counter)").appendingPathExtension(ext)
                counter += 1
            }
        }
    }

    private static func folder(for url: URL, suffix: String) throws -> URL {
        let out = try destination(for: url, ext: "", suffix: suffix)
        let folder = URL(fileURLWithPath: String(out.path.dropLast(out.path.hasSuffix(".") ? 1 : 0)), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: Images

    static func writeImage(_ url: URL, to out: URL, type: UTType, quality: Double = 0.9,
                           scale: CGFloat = 1, keepMetadata: Bool = true, firstFrame: Bool = false, cropRatio: Double = 0) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure(message: "Can't read \(url.lastPathComponent)") }
        guard firstFrame || CGImageSourceGetCount(source) <= 1 else {
            throw Failure(message: "This is a multi-frame image. Use First frame to make a still image; other image tools will not silently discard its frames.")
        }
        try Task.checkCancellation()
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
        // Rendering through a thumbnail applies the orientation and any scale in one step.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(1, max(width, height) * scale)]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure(message: "Can't read \(url.lastPathComponent)")
        }
        if cropRatio > 0 {
            let w = Double(image.width), h = Double(image.height)
            let cropWidth = max(1, floor(min(w, h * cropRatio))), cropHeight = max(1, floor(min(h, w / cropRatio)))
            guard let cropped = image.cropping(to: CGRect(x: floor((w - cropWidth) / 2), y: floor((h - cropHeight) / 2), width: cropWidth, height: cropHeight)) else {
                throw Failure(message: "Couldn't crop this image")
            }
            image = cropped
        }
        // Formats without transparency get a white background instead of black.
        if [UTType.jpeg, .bmp].contains(type), let flattened = flatten(image) { image = flattened }
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(message: "Can't write \(type.preferredFilenameExtension?.uppercased() ?? "image")")
        }
        var written: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if keepMetadata {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyGPSDictionary,
                        kCGImagePropertyTIFFDictionary] {
                if let value = properties[key] { written[key] = value }
            }
        }
        written[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(destination, image, written as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure(message: "Couldn't save \(out.lastPathComponent)") }
    }

    private static func flatten(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func stripMetadata(_ url: URL) throws -> URL {
        switch family(of: url) {
        case .image:
            let ext = url.pathExtension.lowercased()
            let out = try destination(for: url, ext: ext, suffix: "no metadata")
            try writeImage(url, to: out, type: UTType(filenameExtension: ext) ?? .jpeg, quality: 0.95, keepMetadata: false)
            return out
        case .pdf:
            guard let document = PDFDocument(url: url) else { throw Failure(message: "Can't read \(url.lastPathComponent)") }
            document.documentAttributes = [:]
            let out = try destination(for: url, ext: "pdf", suffix: "no metadata")
            guard document.write(to: out) else { throw Failure(message: "Couldn't save \(out.lastPathComponent)") }
            return out
        default: throw Failure(message: "Metadata removal works on images and PDFs")
        }
    }

    // MARK: PDF

    private static func imagesToPDF(_ urls: [URL]) throws -> URL {
        let document = PDFDocument()
        for url in urls {
            try Task.checkCancellation()
            guard !isMultiFrame(url) else { throw Failure(message: "Use First frame before combining multi-frame images.") }
            guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else { throw Failure(message: "Can't read " + url.lastPathComponent) }
            document.insert(page, at: document.pageCount)
        }
        guard document.pageCount > 0, let first = urls.first else { throw Failure(message: "No images to combine") }
        let out = try destination(for: first, ext: "pdf", suffix: urls.count > 1 ? "\(urls.count) images" : nil)
        guard document.write(to: out) else { throw Failure(message: "Couldn't save \(out.lastPathComponent)") }
        return out
    }

    private static func mergePDFs(_ urls: [URL]) throws -> URL {
        let merged = PDFDocument()
        for url in urls {
            try Task.checkCancellation()
            guard let document = PDFDocument(url: url), !document.isLocked else { throw Failure(message: "Can't read or unlock " + url.lastPathComponent) }
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { throw Failure(message: "Couldn’t read page \(index + 1) of " + url.lastPathComponent) }
                merged.insert(page, at: merged.pageCount)
            }
        }
        guard merged.pageCount > 0, let first = urls.first else { throw Failure(message: "No pages to merge") }
        let out = try destination(for: first, ext: "pdf", suffix: "merged")
        guard merged.write(to: out) else { throw Failure(message: "Couldn't save \(out.lastPathComponent)") }
        return out
    }

    private static func pdfToImages(_ url: URL, type: UTType, ext: String) throws -> [URL] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw Failure(message: "Can't read \(url.lastPathComponent)") }
        let target = document.pageCount == 1 ? nil : try folder(for: url, suffix: "pages")
        var outputs: [URL] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw Failure(message: "Couldn't read page \(index + 1)") }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let width = bounds.width * scale, height = bounds.height * scale
            guard width.isFinite, height.isFinite, width > 0, height > 0,
                  width <= 16000, height <= 16000, width * height <= 40_000_000 else {
                throw Failure(message: "Page \(index + 1) is too large to render safely (40 megapixel limit).")
            }
            guard let context = CGContext(data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw Failure(message: "Couldn’t allocate page \(index + 1)") }
            context.setFillColor(.white)
            context.fill(CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            guard let image = context.makeImage() else { throw Failure(message: "Couldn’t render page \(index + 1)") }
            let out = try target.map { $0.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(index + 1).\(ext)") }
                ?? (try destination(for: url, ext: ext))
            guard let destination = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else { throw Failure(message: "Couldn’t write page \(index + 1)") }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw Failure(message: "Couldn't save page \(index + 1)") }
            outputs.append(out)
        }
        return target.map { [$0] } ?? outputs
    }

    private static func splitPDF(_ url: URL) throws -> [URL] {
        guard let document = PDFDocument(url: url), document.pageCount > 1 else { throw Failure(message: "Nothing to split: one page") }
        let target = try folder(for: url, suffix: "pages")
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw Failure(message: "Couldn't read page \(index + 1)") }
            let single = PDFDocument()
            single.insert(page, at: 0)
            guard single.write(to: target.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(index + 1).pdf")) else {
                throw Failure(message: "Couldn't save page \(index + 1)")
            }
        }
        return [target]
    }

    // MARK: Compress

    private static func compress(_ url: URL) async throws -> URL {
        let out: URL
        switch family(of: url) {
        case .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure(message: "Can't read " + url.lastPathComponent) }
            let alpha = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyHasAlpha] as? Bool ?? false
            let ext = url.pathExtension.lowercased()
            let type: UTType = alpha ? .png : ["png", "tiff", "tif", "bmp"].contains(ext) ? .jpeg : (UTType(filenameExtension: ext) ?? .jpeg)
            out = try destination(for: url, ext: type.preferredFilenameExtension ?? ext, suffix: "compressed")
            try writeImage(url, to: out, type: type, quality: 0.6)
        case .pdf:
            guard let document = PDFDocument(url: url), !document.isLocked else { throw Failure(message: "Can't read or unlock " + url.lastPathComponent) }
            guard let filter = QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")) else {
                throw Failure(message: "PDF compression isn't available on this Mac.")
            }
            out = try destination(for: url, ext: "pdf", suffix: "compressed")
            guard document.write(to: out, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]) else {
                throw Failure(message: "Couldn't save the compressed PDF")
            }
        case .video:
            out = try await export(url, preset: AVAssetExportPreset1920x1080, type: .mp4, ext: "mp4", suffix: "compressed")
        case .audio:
            out = try await export(url, preset: AVAssetExportPresetAppleM4A, type: .m4a, ext: "m4a", suffix: "compressed")
        default: throw Failure(message: "Compression works on images, PDFs, video and audio")
        }
        let originalSize = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let outputSize = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard outputSize > 0, outputSize < originalSize else {
            try? FileManager.default.removeItem(at: out)
            throw Failure(message: "Couldn't make this file smaller with the native compression preset. The original is unchanged.")
        }
        return out
    }

    private static func byteCount(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? Int64.max
    }

    private static func targetSize(_ url: URL, options: Options) async throws -> URL {
        let limit = max(10_000, min(2_000_000_000, options.maximumBytes))
        if byteCount(url) <= limit {
            let out = try destination(for: url, ext: url.pathExtension, suffix: "ready to share")
            try FileManager.default.copyItem(at: url, to: out)
            return out
        }
        if family(of: url) == .video {
            for preset in [AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720, AVAssetExportPreset640x480, AVAssetExportPresetLowQuality] {
                try Task.checkCancellation()
                let out = try await export(url, preset: preset, type: .mp4, ext: "mp4", suffix: "smaller")
                if byteCount(out) <= limit { return out }
                transaction?.discard(out)
                if transaction == nil { try? FileManager.default.removeItem(at: out) }
            }
            throw Failure(message: "The native video presets couldn't reach this size. Try a larger target or trim the video first.")
        }
        guard family(of: url) == .image else { throw Failure(message: "Target size supports images and video.") }
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        let alpha = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }?[kCGImagePropertyHasAlpha] as? Bool ?? false
        let type: UTType = alpha ? .png : .jpeg
        let out = try destination(for: url, ext: alpha ? "png" : "jpg", suffix: "smaller")
        var scale: CGFloat = 1
        for _ in 0..<16 {
            try Task.checkCancellation()
            for quality in alpha ? [1] : [min(1, max(0.1, options.quality)), 0.65, 0.45] {
                try writeImage(url, to: out, type: type, quality: quality, scale: scale, keepMetadata: false)
                if byteCount(out) <= limit { return out }
            }
            scale *= 0.8
        }
        throw Failure(message: "Couldn't reach the target size without removing transparency. Try a larger target.")
    }

    // MARK: Video and audio

    private static func export(_ url: URL, preset: String, type: AVFileType, ext: String, suffix: String? = nil) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure(message: "Can't convert \(url.lastPathComponent)")
        }
        let out = try destination(for: url, ext: ext, suffix: suffix)
        let progress = reportProgress
        let observer = Task {
            while !Task.isCancelled {
                if let progress { await progress(Double(session.progress)) }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { observer.cancel() }
        try await withTaskCancellationHandler {
            try await session.export(to: out, as: type)
            try Task.checkCancellation()
        } onCancel: { session.cancelExport() }
        return out
    }

    private static func snapshot(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let (image, _) = try await generator.image(at: CMTimeMultiplyByFloat64(duration, multiplier: 0.5))
        let out = try destination(for: url, ext: "png", suffix: "snapshot")
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure(message: "Couldn't save the snapshot")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure(message: "Couldn't save the snapshot") }
        return out
    }

    /// A bounded looping clip; defaults to eight seconds at 12 fps and 480 pixels.
    private static func videoToGIF(_ url: URL, options: Options = Options(maximumDimension: 480)) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let start = min(max(0, options.gifStart), max(0, duration - 0.1))
        let seconds = min(max(0.1, min(30, options.gifDuration)), duration - start)
        guard seconds.isFinite, seconds > 0 else { throw Failure(message: "This video has no usable duration.") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let dimension = max(64, min(960, options.maximumDimension))
        generator.maximumSize = CGSize(width: dimension, height: dimension)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let fps = min(30, max(1, options.gifFPS))
        let count = max(1, Int(seconds * fps))
        guard Double(count) * Double(dimension * dimension) <= 120_000_000 else {
            throw Failure(message: "This GIF combination is too large. Reduce its duration, frame rate or longest edge.")
        }
        let out = try destination(for: url, ext: "gif")
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw Failure(message: "Couldn't create the GIF")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for index in 0..<count {
            try Task.checkCancellation()
            let (image, _) = try await generator.image(at: CMTime(seconds: start + Double(index) / fps, preferredTimescale: 600))
            CGImageDestinationAddImage(destination, image, frame)
            if let reportProgress { await reportProgress(Double(index + 1) / Double(count)) }
        }
        guard CGImageDestinationFinalize(destination) else { throw Failure(message: "Couldn't save the GIF") }
        return out
    }

    /// WAV, AIFF or CAF as 16-bit PCM at the source's sample rate.
    private static func writePCM(_ url: URL, ext: String) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
                                       AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: ext == "aiff"]
        let out = try destination(for: url, ext: ext)
        let output = try AVAudioFile(forWriting: out, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else { throw Failure(message: "Out of memory") }
        while input.framePosition < input.length {
            try Task.checkCancellation()
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
        return out
    }

    // MARK: Documents

    @MainActor
    private static func convertDocument(_ url: URL, ext: String) async throws -> URL {
        let text = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        let out = try destination(for: url, ext: ext)
        let range = NSRange(location: 0, length: text.length)
        switch ext {
        case "pdf":
            // Laid out on US Letter pages with one-inch margins.
            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
            view.textStorage?.setAttributedString(text)
            let info = NSPrintInfo()
            info.paperSize = NSSize(width: 612, height: 792)
            info.topMargin = 72; info.bottomMargin = 72; info.leftMargin = 72; info.rightMargin = 72
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = out
            let operation = NSPrintOperation(view: view, printInfo: info)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            guard operation.run() else { throw Failure(message: "Couldn't make the PDF") }
        case "txt":
            try text.string.write(to: out, atomically: true, encoding: .utf8)
        default:
            let type: NSAttributedString.DocumentType = ext == "docx" ? .officeOpenXML : ext == "rtf" ? .rtf
                : ext == "odt" ? .openDocument : .html
            let data = try text.data(from: range, documentAttributes: [.documentType: type])
            try data.write(to: out)
        }
        return out
    }

    // MARK: Archives

    private static func zip(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw Failure(message: "Nothing to zip") }
        let parent = first.deletingLastPathComponent()
        let out = try destination(for: first, ext: "zip", suffix: urls.count > 1 ? "\(urls.count) items" : nil)
        if urls.count == 1 {
            try runTool("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, out.path])
        } else if urls.allSatisfy({ $0.deletingLastPathComponent() == parent }) {
            try runTool("/usr/bin/zip", ["-r", "-q", "-y", out.path] + urls.map(\.lastPathComponent), in: parent)
        } else {
            try runTool("/usr/bin/zip", ["-r", "-q", "-y", "-j", out.path] + urls.map(\.path))
        }
        return out
    }

    private static func unzip(_ url: URL) throws -> URL {
        let target = try folder(for: url, suffix: "unzipped")
        try runTool("/usr/bin/ditto", ["-x", "-k", url.path, target.path])
        return target
    }

    private static func runTool(_ path: String, _ arguments: [String], in directory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                let deadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard process.terminationStatus == 0 else { throw Failure(message: "\((path as NSString).lastPathComponent) failed") }
    }

    /// Shrinks an image until it's under 1 MB (GitHub, email, forms): JPEG quality
    /// first, then size, a step at a time. Transparent PNGs stay PNG and only shrink.
    static func underOneMegabyte(_ url: URL) throws -> URL {
        let limit = 1_000_000
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure(message: "Can't read \(url.lastPathComponent)") }
        let hasAlpha = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyHasAlpha] as? Bool ?? false
        let keepsPNG = hasAlpha
        let type: UTType = keepsPNG ? .png : .jpeg
        let out = try destination(for: url, ext: keepsPNG ? "png" : "jpg", suffix: "under 1 MB")
        // Read the size fresh each time (URL resource values are cached).
        let size = { ((try? FileManager.default.attributesOfItem(atPath: out.path))?[.size] as? Int) ?? .max }
        var scale: CGFloat = 1
        for _ in 0..<12 {
            try Task.checkCancellation()
            for quality in keepsPNG ? [1.0] : [0.85, 0.7, 0.55] {
                try writeImage(url, to: out, type: type, quality: quality, scale: scale, keepMetadata: false)
                if size() <= limit { return out }
            }
            scale *= 0.8
        }
        throw Failure(message: "Couldn't get \(url.lastPathComponent) under 1 MB")
    }
}

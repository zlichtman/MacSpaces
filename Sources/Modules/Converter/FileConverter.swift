import AppKit
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
    struct Action: Identifiable, Hashable {
        let id: String
        let title: String
        let symbol: String?
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
            switch family {
            case .image:
                // Combining into one PDF only makes sense for several images.
                return [Action(id: "tool.compress", title: "Compress", symbol: "arrow.down.right.and.arrow.up.left"),
                        Action(id: "tool.strip", title: "Metadata", symbol: "eye.slash"),
                        Action(id: "tool.half", title: "Half size", symbol: "square.resize.down")]
                    + (urls.count > 1 ? [Action(id: "tool.pdf", title: "One PDF", symbol: "doc.richtext")] : [])
                    + [Action(id: "zip", title: "ZIP", symbol: "doc.zipper")]
            case .pdf:
                // Split needs more than one page; merge needs more than one file.
                let pages = urls.count == 1 ? (PDFDocument(url: urls[0])?.pageCount ?? 0) : 0
                return [Action(id: "tool.compress", title: "Compress", symbol: "arrow.down.right.and.arrow.up.left")]
                    + (pages > 1 ? [Action(id: "tool.split", title: "Split pages", symbol: "square.split.2x1")] : [])
                    + (urls.count > 1 ? [Action(id: "tool.merge", title: "Merge", symbol: "square.stack")] : [])
                    + [Action(id: "tool.strip", title: "Metadata", symbol: "eye.slash"),
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
            formats = [Action(id: "pdf.png", title: "PNG", symbol: nil), Action(id: "pdf.jpg", title: "JPG", symbol: nil),
                       Action(id: "pdf.txt", title: "TXT", symbol: nil)]
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

    // MARK: Running

    /// Runs one action on every file and returns the files it wrote.
    static func run(_ action: Action, on urls: [URL], progress: @escaping @MainActor (Double) -> Void) async throws -> [URL] {
        if action.id == "zip" { return [try zip(urls)] }
        if action.id == "tool.pdf" { return [try imagesToPDF(urls)] }
        if action.id == "tool.merge" { return [try mergePDFs(urls)] }
        var outputs: [URL] = []
        for (index, url) in urls.enumerated() {
            outputs += try await runOne(action, on: url)
            await progress(Double(index + 1) / Double(urls.count))
        }
        return outputs
    }

    private static func runOne(_ action: Action, on url: URL) async throws -> [URL] {
        let parts = action.id.split(separator: ".").map(String.init)
        guard parts.count == 2 else { throw Failure(message: "Unknown action") }
        switch (parts[0], parts[1]) {
        case ("image", "pdf"): return [try imagesToPDF([url])]
        case ("image", let target):
            guard let type = imageTargets.first(where: { $0.id == target })?.type else { throw Failure(message: "\(target.uppercased()) isn't supported") }
            let out = destination(for: url, ext: target)
            try writeImage(url, to: out, type: type)
            return [out]
        case ("pdf", "txt"):
            // Scanned or image-only PDFs have no text layer to save.
            guard let text = PDFDocument(url: url)?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Failure(message: "No text in \(url.lastPathComponent)")
            }
            let out = destination(for: url, ext: "txt")
            try text.write(to: out, atomically: true, encoding: .utf8)
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
        case ("tool", "unzip"): return [try unzip(url)]
        case ("tool", "snapshot"): return [try await snapshot(url)]
        case ("tool", "gif"): return [try await videoToGIF(url)]
        case ("tool", "split"): return try splitPDF(url)
        case ("tool", "compress"): return [try await compress(url)]
        case ("tool", "strip"): return [try stripMetadata(url)]
        case ("tool", "half"):
            let ext = url.pathExtension.lowercased()
            let type = UTType(filenameExtension: ext) ?? .png
            let out = destination(for: url, ext: ext, suffix: "half size")
            try writeImage(url, to: out, type: type, scale: 0.5)
            return [out]
        default: throw Failure(message: "\(action.title) isn't available for \(url.lastPathComponent)")
        }
    }

    // MARK: Destinations

    /// Beside the original (or in Downloads when that folder is read-only),
    /// never replacing an existing file.
    static func destination(for url: URL, ext: String, suffix: String? = nil) -> URL {
        var folder = url.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: folder.path) {
            folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        let base = url.deletingPathExtension().lastPathComponent + (suffix.map { " (\($0))" } ?? "")
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    private static func folder(for url: URL, suffix: String) throws -> URL {
        let out = destination(for: url, ext: "", suffix: suffix)
        let folder = URL(fileURLWithPath: String(out.path.dropLast(out.path.hasSuffix(".") ? 1 : 0)), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: Images

    static func writeImage(_ url: URL, to out: URL, type: UTType, quality: Double = 0.9,
                           scale: CGFloat = 1, keepMetadata: Bool = true) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure(message: "Can't read \(url.lastPathComponent)") }
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
            let out = destination(for: url, ext: ext, suffix: "no metadata")
            try writeImage(url, to: out, type: UTType(filenameExtension: ext) ?? .jpeg, quality: 0.95, keepMetadata: false)
            return out
        case .pdf:
            guard let document = PDFDocument(url: url) else { throw Failure(message: "Can't read \(url.lastPathComponent)") }
            document.documentAttributes = [:]
            let out = destination(for: url, ext: "pdf", suffix: "no metadata")
            guard document.write(to: out) else { throw Failure(message: "Couldn't save \(out.lastPathComponent)") }
            return out
        default: throw Failure(message: "Metadata removal works on images and PDFs")
        }
    }

    // MARK: PDF

    private static func imagesToPDF(_ urls: [URL]) throws -> URL {
        let document = PDFDocument()
        for url in urls {
            guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else { continue }
            document.insert(page, at: document.pageCount)
        }
        guard document.pageCount > 0, let first = urls.first else { throw Failure(message: "No images to combine") }
        let out = destination(for: first, ext: "pdf", suffix: urls.count > 1 ? "\(urls.count) images" : nil)
        guard document.write(to: out) else { throw Failure(message: "Couldn't save \(out.lastPathComponent)") }
        return out
    }

    private static func mergePDFs(_ urls: [URL]) throws -> URL {
        let merged = PDFDocument()
        for url in urls {
            guard let document = PDFDocument(url: url) else { continue }
            for index in 0..<document.pageCount {
                if let page = document.page(at: index) { merged.insert(page, at: merged.pageCount) }
            }
        }
        guard merged.pageCount > 0, let first = urls.first else { throw Failure(message: "No pages to merge") }
        let out = destination(for: first, ext: "pdf", suffix: "merged")
        guard merged.write(to: out) else { throw Failure(message: "Couldn't save \(out.lastPathComponent)") }
        return out
    }

    private static func pdfToImages(_ url: URL, type: UTType, ext: String) throws -> [URL] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw Failure(message: "Can't read \(url.lastPathComponent)") }
        let target = document.pageCount == 1 ? nil : try folder(for: url, suffix: "pages")
        var outputs: [URL] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            guard let context = CGContext(data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
            context.setFillColor(.white)
            context.fill(CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            guard let image = context.makeImage() else { continue }
            let out = target.map { $0.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(index + 1).\(ext)") }
                ?? destination(for: url, ext: ext)
            guard let destination = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            if CGImageDestinationFinalize(destination) { outputs.append(out) }
        }
        return target.map { [$0] } ?? outputs
    }

    private static func splitPDF(_ url: URL) throws -> [URL] {
        guard let document = PDFDocument(url: url), document.pageCount > 1 else { throw Failure(message: "Nothing to split: one page") }
        let target = try folder(for: url, suffix: "pages")
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            single.write(to: target.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(index + 1).pdf"))
        }
        return [target]
    }

    // MARK: Compress

    private static func compress(_ url: URL) async throws -> URL {
        switch family(of: url) {
        case .image:
            let ext = url.pathExtension.lowercased()
            // Lossless formats become JPEG; lossy ones re-encode at a lower quality.
            let lossless = ["png", "tiff", "tif", "bmp"].contains(ext)
            let out = destination(for: url, ext: lossless ? "jpg" : ext, suffix: "compressed")
            try writeImage(url, to: out, type: lossless ? .jpeg : (UTType(filenameExtension: ext) ?? .jpeg), quality: 0.6)
            return out
        case .pdf:
            guard let document = PDFDocument(url: url) else { throw Failure(message: "Can't read \(url.lastPathComponent)") }
            let out = destination(for: url, ext: "pdf", suffix: "compressed")
            let filterURL = URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")
            var options: [PDFDocumentWriteOption: Any] = [:]
            if let filter = QuartzFilter(url: filterURL) { options[PDFDocumentWriteOption(rawValue: "QuartzFilter")] = filter }
            guard document.write(to: out, withOptions: options) else { throw Failure(message: "Couldn't save \(out.lastPathComponent)") }
            return out
        case .video:
            return try await export(url, preset: AVAssetExportPreset1920x1080, type: .mp4, ext: "mp4", suffix: "compressed")
        case .audio:
            return try await export(url, preset: AVAssetExportPresetAppleM4A, type: .m4a, ext: "m4a", suffix: "compressed")
        default: throw Failure(message: "Compression works on images, PDFs, video and audio")
        }
    }

    // MARK: Video and audio

    private static func export(_ url: URL, preset: String, type: AVFileType, ext: String, suffix: String? = nil) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure(message: "Can't convert \(url.lastPathComponent)")
        }
        let out = destination(for: url, ext: ext, suffix: suffix)
        try await session.export(to: out, as: type)
        return out
    }

    private static func snapshot(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let (image, _) = try await generator.image(at: CMTimeMultiplyByFloat64(duration, multiplier: 0.5))
        let out = destination(for: url, ext: "png", suffix: "snapshot")
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure(message: "Couldn't save the snapshot")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure(message: "Couldn't save the snapshot") }
        return out
    }

    /// Up to the first 15 seconds at 12 frames a second, 480 pixels wide, looping.
    private static func videoToGIF(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let seconds = min(15, try await asset.load(.duration).seconds)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let fps = 12.0
        let count = max(1, Int(seconds * fps))
        let out = destination(for: url, ext: "gif")
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw Failure(message: "Couldn't create the GIF")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for index in 0..<count {
            let (image, _) = try await generator.image(at: CMTime(seconds: Double(index) / fps, preferredTimescale: 600))
            CGImageDestinationAddImage(destination, image, frame)
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
        let out = destination(for: url, ext: ext)
        let output = try AVAudioFile(forWriting: out, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else { throw Failure(message: "Out of memory") }
        while input.framePosition < input.length {
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
        let out = destination(for: url, ext: ext)
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
        let out = destination(for: first, ext: "zip", suffix: urls.count > 1 ? "\(urls.count) items" : nil)
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
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(message: "\((path as NSString).lastPathComponent) failed") }
    }
}

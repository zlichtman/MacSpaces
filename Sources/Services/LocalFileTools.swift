import AppKit
import CoreImage
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Local processing only. A result is saved to a user-selected destination;
/// the source is never edited. The worker queue keeps Vision off the UI thread.
enum LocalFileTools {
    enum Operation: String {
        case png, jpeg, extractText, removeBackground
        var title: String {
            switch self {
            case .png: return "Convert to PNG"
            case .jpeg: return "Convert to JPEG"
            case .extractText: return "Extract Text"
            case .removeBackground: return "Remove Background"
            }
        }
        var contentType: UTType { self == .extractText ? .plainText : self == .jpeg ? .jpeg : .png }
        var suffix: String { self == .extractText ? "txt" : self == .jpeg ? "jpg" : "png" }
    }
    enum Failure: LocalizedError {
        case unsupported, tooLarge, noText, noSubject, requiresNewerSystem, lockedPDF
        var errorDescription: String? {
            switch self {
            case .unsupported: return "This file cannot be processed as an image or PDF."
            case .tooLarge: return "Use an image under 40 megapixels, or a PDF with at most 100 pages, under 100 MB."
            case .noText: return "No readable text was found."
            case .noSubject: return "No foreground subject was found."
            case .requiresNewerSystem: return "Background removal requires macOS 14 or later."
            case .lockedPDF: return "Unlock the PDF before extracting its text."
            }
        }
    }
    private static let queue = DispatchQueue(label: "dev.opensource.MacSpaces.file-tools", qos: .userInitiated)

    static func process(_ url: URL, operation: Operation) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try autoreleasepool { try transform(url, operation: operation) }) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func transform(_ url: URL, operation: Operation) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard url.isFileURL, values.isRegularFile == true else { throw Failure.unsupported }
        guard (values.fileSize ?? Int.max) <= 100 * 1024 * 1024 else { throw Failure.tooLarge }
        if operation == .extractText, url.pathExtension.lowercased() == "pdf" {
            return try extractPDF(url)
        }
        let image = try loadImage(url)
        switch operation {
        case .extractText:
            let text = try recognize(image)
            guard !text.isEmpty else { throw Failure.noText }
            return Data(text.utf8)
        case .removeBackground:
            if #available(macOS 14, *) {
                let request = VNGenerateForegroundInstanceMaskRequest()
                let handler = VNImageRequestHandler(cgImage: image)
                try handler.perform([request])
                guard let result = request.results?.first, !result.allInstances.isEmpty else { throw Failure.noSubject }
                let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                           croppedToInstancesExtent: false)
                let ci = CIImage(cvPixelBuffer: buffer)
                guard let output = CIContext().createCGImage(ci, from: ci.extent) else { throw Failure.unsupported }
                return try encode(output, jpeg: false)
            } else { throw Failure.requiresNewerSystem }
        case .png: return try encode(image, jpeg: false)
        case .jpeg: return try encode(image, jpeg: true)
        }
    }

    private static func loadImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw Failure.unsupported }
        guard width > 0, height > 0, width <= 40_000_000 / height else { throw Failure.tooLarge }
        // Applies EXIF orientation, preserving the original pixel dimensions.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw Failure.unsupported }
        return image
    }

    private static func encode(_ image: CGImage, jpeg: Bool) throws -> Data {
        var output = image
        if jpeg {
            guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw Failure.unsupported }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let flattened = context.makeImage() else { throw Failure.unsupported }
            output = flattened
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, (jpeg ? UTType.jpeg : .png).identifier as CFString, 1, nil) else { throw Failure.unsupported }
        CGImageDestinationAddImage(destination, output,
            jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unsupported }
        return data as Data
    }

    private static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func extractPDF(_ url: URL) throws -> Data {
        guard let document = PDFDocument(url: url) else { throw Failure.unsupported }
        guard !document.isLocked else { throw Failure.lockedPDF }
        guard document.pageCount <= 100 else { throw Failure.tooLarge }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            let text: String = try autoreleasepool {
                guard let page = document.page(at: index) else { throw Failure.unsupported }
                if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
                let bounds = page.bounds(for: .mediaBox)
                guard bounds.width > 0, bounds.height > 0 else { throw Failure.unsupported }
                let scale = min(3, 2400 / max(bounds.width, bounds.height))
                let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
                guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Failure.unsupported }
                return try recognize(cg)
            }
            pages.append(text)
        }
        guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw Failure.noText }
        return Data(pages.joined(separator: "\n\n--- Page break ---\n\n").utf8)
    }
}

import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Converts images (ImageIO) and audio / video (AVFoundation). Results land next to the source.
@MainActor
enum FileConverter {
    enum Format: String, CaseIterable, Identifiable {
        case png, jpeg, heic, tiff, mp4, mov, m4a
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }

        var type: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .heic: .heic
            case .tiff: .tiff
            case .mp4: .mpeg4Movie
            case .mov: .quickTimeMovie
            case .m4a: .mpeg4Audio
            }
        }

        var fileExtension: String {
            switch self {
            case .jpeg: "jpg"
            default: rawValue
            }
        }

        var isImage: Bool { [.png, .jpeg, .heic, .tiff].contains(self) }
    }

    /// Formats a set of files can all be converted to.
    static func formats(for urls: [URL]) -> [Format] {
        let types = urls.compactMap { UTType(filenameExtension: $0.pathExtension) }
        guard !types.isEmpty else { return [] }
        if types.allSatisfy({ $0.conforms(to: .image) }) { return [.png, .jpeg, .heic, .tiff] }
        if types.allSatisfy({ $0.conforms(to: .movie) }) { return [.mp4, .mov, .m4a] }
        if types.allSatisfy({ $0.conforms(to: .audio) }) { return [.m4a] }
        return []
    }

    static func convert(_ urls: [URL], to format: Format) {
        Task {
            for url in urls {
                let output = uniqueOutputURL(for: url, format: format)
                let name = url.lastPathComponent
                LiveActivityCenter.shared.show(.conversion(name: name, progress: 0, failed: false), duration: 600)
                let success: Bool
                if format.isImage {
                    success = await Task.detached { convertImage(url, to: output, format: format) }.value
                } else {
                    success = await convertMedia(url, to: output, format: format) { progress in
                        LiveActivityCenter.shared.show(.conversion(name: name, progress: progress, failed: false), duration: 600)
                    }
                }
                LiveActivityCenter.shared.show(.conversion(name: name, progress: 1, failed: !success), duration: 2.5)
                if success { ShelfStore.shared.add(urls: [output]) }
            }
        }
    }

    private static func uniqueOutputURL(for url: URL, format: Format) -> URL {
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent("\(base).\(format.fileExtension)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index).\(format.fileExtension)")
            index += 1
        }
        return candidate
    }

    nonisolated private static func convertImage(_ url: URL, to output: URL, format: Format) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, format.type.identifier as CFString, 1, nil) else { return false }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImageFromSource(destination, source, 0, options)
        return CGImageDestinationFinalize(destination)
    }

    private static func convertMedia(_ url: URL, to output: URL, format: Format, progress: @escaping @MainActor (Double) -> Void) async -> Bool {
        let asset = AVURLAsset(url: url)
        let preset = format == .m4a ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return false }
        let fileType: AVFileType = switch format {
        case .mp4: .mp4
        case .mov: .mov
        default: .m4a
        }
        let monitor = Task {
            for await state in session.states(updateInterval: 0.2) {
                if case let .exporting(p) = state { progress(p.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        do {
            try await session.export(to: output, as: fileType)
            return true
        } catch {
            NSLog("Notchy: conversion failed: \(error)")
            return false
        }
    }
}

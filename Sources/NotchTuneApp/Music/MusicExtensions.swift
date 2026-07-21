import Foundation
import AppKit

// MARK: - NSImage

extension NSImage {
    func musicIsEmpty() -> Bool {
        // ScriptingBridge may return NSAppleEventDescriptor typed as NSImage; guard at runtime
        guard self.isKind(of: NSImage.self) else { return true }
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let dataProvider = cgImage.dataProvider else { return true }
        let pixelData = dataProvider.data
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
        let imageWidth = Int(self.size.width)
        let imageHeight = Int(self.size.height)
        for x in 0..<imageWidth {
            for y in 0..<imageHeight {
                let pixelIndex = ((imageWidth * y) + x) * 4
                let r = data[pixelIndex]
                let g = data[pixelIndex + 1]
                let b = data[pixelIndex + 2]
                let a = data[pixelIndex + 3]
                if a != 0 { if r != 0 || g != 0 || b != 0 { return false } }
            }
        }
        return true
    }

    var musicAverageColor: NSColor? {
        guard isValid else { return nil }
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        guard let cgImageRef = cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else { return nil }
        let inputImage = CIImage(cgImage: cgImageRef)
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y,
                                    z: inputImage.extent.size.width, w: inputImage.extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]),
              let outputImage = filter.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull!])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return NSColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255,
                       blue: CGFloat(bitmap[2]) / 255, alpha: CGFloat(bitmap[3]) / 255)
    }
}

// MARK: - NSError

extension NSError {
    static func musicCheckOSStatus(_ closure: () -> OSStatus) throws {
        guard let error = NSError(musicOsstatus: closure()) else { return }
        throw error
    }

    convenience init?(musicOsstatus osstatus: OSStatus) {
        guard osstatus != 0 else { return nil }
        self.init(domain: NSOSStatusErrorDomain, code: Int(osstatus), userInfo: nil)
    }
}

// MARK: - DateComponentsFormatter

extension DateComponentsFormatter {
    static let musicPlaybackTimeWithHours: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .positional
        f.zeroFormattingBehavior = .pad
        return f
    }()

    static let musicPlaybackTime: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.unitsStyle = .positional
        f.zeroFormattingBehavior = .pad
        return f
    }()
}

// MARK: - Comparable

extension Comparable {
    func musicClamped(to range: ClosedRange<Self>) -> Self {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

// MARK: - BinaryFloatingPoint

extension BinaryFloatingPoint {
    func musicMap(from source: ClosedRange<Self>, to target: ClosedRange<Self>) -> Self {
        guard source.upperBound != source.lowerBound else { return target.lowerBound }
        let ratio = (self - source.lowerBound) / (source.upperBound - source.lowerBound)
        return target.lowerBound + ratio * (target.upperBound - target.lowerBound)
    }
}

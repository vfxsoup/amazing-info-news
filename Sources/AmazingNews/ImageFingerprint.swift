import Foundation
import CoreGraphics
import ImageIO

/// A tiny visual fingerprint of a picture, used to spot images that *look* the same
/// even when the files differ (resized copies, the same press photo from two outlets,
/// a company's stock logo art reused across stories).
struct ImageFingerprint {
    /// 64-bit difference hash: structure/edges at 9×8.
    let dHash: UInt64
    /// 4×4 grid of average colours (48 values, 0–255): overall look.
    let colors: [UInt8]

    init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 256,
              ] as CFDictionary) ?? CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        guard let gray = Self.pixels(img, width: 9, height: 8, gray: true),
              let rgb = Self.pixels(img, width: 4, height: 4, gray: false) else { return nil }
        var h: UInt64 = 0
        for y in 0..<8 { for x in 0..<8 {
            h <<= 1
            if gray[y * 9 + x] > gray[y * 9 + x + 1] { h |= 1 }
        } }
        dHash = h
        // RGBA -> RGB
        colors = stride(from: 0, to: rgb.count, by: 4).flatMap { [rgb[$0], rgb[$0 + 1], rgb[$0 + 2]] }
    }

    private static func pixels(_ img: CGImage, width: Int, height: Int, gray: Bool) -> [UInt8]? {
        let bpp = gray ? 1 : 4
        var buf = [UInt8](repeating: 0, count: width * height * bpp)
        let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        guard let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * bpp, space: space, bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buf
    }

    /// Bits that differ in the structure hash (0 = identical, 64 = opposite).
    func structureDistance(_ o: ImageFingerprint) -> Int { (dHash ^ o.dHash).nonzeroBitCount }

    /// Average per-channel colour difference across the 4×4 grid (0–255).
    func colorDistance(_ o: ImageFingerprint) -> Double {
        let total = zip(colors, o.colors).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(colors.count)
    }

    /// Average colour of the whole picture.
    var meanColor: (Double, Double, Double) {
        var r = 0.0, g = 0.0, b = 0.0
        for i in stride(from: 0, to: colors.count, by: 3) { r += Double(colors[i]); g += Double(colors[i + 1]); b += Double(colors[i + 2]) }
        let n = Double(colors.count / 3)
        return (r / n, g / n, b / n)
    }

    /// True when two pictures would look like a repeat to a reader.
    /// `sameCompany`: the two stories are about the same company, where outlets reuse brand artwork.
    func looksLike(_ o: ImageFingerprint, sameCompany: Bool = false) -> Bool {
        let s = structureDistance(o), c = colorDistance(o)
        if s <= 10 && c < 45 { return true }          // same photo, resized or re-cropped
        if s <= 22 && c < 18 { return true }          // same photo with text or logos added
        if sameCompany {
            let (a, b) = (meanColor, o.meanColor)
            let d = (abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)) / 3
            let saturated = max(a.0, a.1, a.2) - min(a.0, a.1, a.2) > 40
            if d < 25 && saturated { return true }    // same brand colour scheme (e.g. Anthropic orange)
        }
        return false
    }
}

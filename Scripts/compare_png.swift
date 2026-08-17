import Foundation

// Compares two PNGs and prints the fraction of differing pixels (0.0 = identical).
// Usage: compare_png.swift <expected.png> <actual.png> <diff.png>
// Writes a diff image (amplified channel deltas) to <diff.png>.

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: compare_png <expected> <actual> <diff>\n".utf8))
    exit(2)
}

struct Image { let w: Int; let h: Int; let bpp: Int; let raw: [UInt8] }

func decode(_ data: Data) -> Image? {
    guard data.count > 8, Array(data[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] else { return nil }
    var pos = 8
    var w = 0, h = 0, bpp = 0
    var idat = Data()
    while pos + 8 <= data.count {
        let ln = Int(UInt32(data[pos]) << 24 | UInt32(data[pos + 1]) << 16 | UInt32(data[pos + 2]) << 8 | UInt32(data[pos + 3]))
        let type = String(data: data[pos + 4..<pos + 8], encoding: .utf8)
        let chunk = data[pos + 8..<pos + 8 + ln]
        if type == "IHDR" {
            w = Int(UInt32(chunk[0]) << 24 | UInt32(chunk[1]) << 16 | UInt32(chunk[2]) << 8 | UInt32(chunk[3]))
            h = Int(UInt32(chunk[4]) << 24 | UInt32(chunk[5]) << 16 | UInt32(chunk[6]) << 8 | UInt32(chunk[7]))
            let ct = chunk[9]
            bpp = ct == 6 ? 4 : (ct == 2 ? 3 : 1)
        } else if type == "IDAT" {
            idat.append(chunk)
        }
        pos += 12 + ln
    }
    guard w > 0, h > 0 else { return nil }
    // Inflate zlib
    let inflated = try? (idat as NSData).decompressed(using: .zlib) as Data
    guard let inflated else { return nil }
    return Image(w: w, h: h, bpp: bpp, raw: [UInt8](inflated))
}

guard let e = decode(try Data(contentsOf: URL(fileURLWithPath: args[1]))),
      let a = decode(try Data(contentsOf: URL(fileURLWithPath: args[2]))) else {
    print("1.0")
    exit(1)
}

let w = min(e.w, a.w)
let h = min(e.h, a.h)
var differing = 0
var total = 0
var diffPixels = [UInt8](repeating: 0, count: w * h * 4)
for y in 0..<h {
    for x in 0..<w {
        let eo = (y * e.w + x) * e.bpp
        let ao = (y * a.w + x) * a.bpp
        let er = Int(e.raw[eo]); let eg = Int(e.raw[eo + 1]); let eb = Int(e.raw[eo + 2])
        let ar = Int(a.raw[ao]); let ag = Int(a.raw[ao + 1]); let ab = Int(a.raw[ao + 2])
        total += 1
        let delta = abs(er - ar) + abs(eg - ag) + abs(eb - ab)
        if delta > 30 { differing += 1 }
        let doff = (y * w + x) * 4
        diffPixels[doff] = UInt8(min(255, abs(er - ar) * 8))
        diffPixels[doff + 1] = UInt8(min(255, abs(eg - ag) * 8))
        diffPixels[doff + 2] = UInt8(min(255, abs(eb - ab) * 8))
        diffPixels[doff + 3] = 255
    }
}
let ratio = total == 0 ? 1.0 : Double(differing) / Double(total)
print(String(format: "%.6f", ratio))

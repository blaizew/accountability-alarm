import Foundation

struct ConfettiPalette: Equatable {
    /// RGB hex ints, e.g. 0xD9BFA6.
    let colors: [UInt32]
}

enum ConfettiPalettes {
    /// House palette: L.Palette fg, the escalation ambers, and bg3.
    static let house = ConfettiPalette(colors: [0xD9BFA6, 0xCF7D44, 0xE28D4F, 0xD9A850])

    /// The 36 palettes from confettipage.com, in the site's order.
    static let site: [ConfettiPalette] = [
        ConfettiPalette(colors: [0x332f48, 0xf2d9e6, 0xec4c4c, 0x772c93]),
        ConfettiPalette(colors: [0xfcfff4, 0x3b395e, 0x6f6ca6, 0x59bec2]),
        ConfettiPalette(colors: [0xf8fcfb, 0x342926, 0x8b7368, 0xf7bf9b]),
        ConfettiPalette(colors: [0x64e4ec, 0x283145, 0x0078f5, 0xefe5e1]),
        ConfettiPalette(colors: [0xe1a750, 0x001c2d, 0x455c57, 0xcad7ca]),
        ConfettiPalette(colors: [0xfbfdfc, 0x370787, 0x8661f4, 0xf791f0]),
        ConfettiPalette(colors: [0xfaf9fd, 0x10396a, 0xf33452, 0xfaa742]),
        ConfettiPalette(colors: [0x67411c, 0x792061, 0xeb60a5, 0xfbf8ed]),
        ConfettiPalette(colors: [0xebeff4, 0x221d18, 0x7939e1, 0xc0b5d2]),
        ConfettiPalette(colors: [0xfffcfb, 0x712b3d, 0xda604b, 0xebb431]),
        ConfettiPalette(colors: [0x433d5d, 0xffcd40, 0xf6f6f8, 0x5e6974]),
        ConfettiPalette(colors: [0xbed3af, 0x150f00, 0x5c4710, 0xc9c734]),
        ConfettiPalette(colors: [0x094bcf, 0xfeb959, 0xfeffff, 0x6b8eed]),
        ConfettiPalette(colors: [0xfbfefd, 0x00186a, 0x003afb, 0x7aa8f7]),
        ConfettiPalette(colors: [0x38251e, 0xf3b74d, 0xe47a54, 0xa4422c]),
        ConfettiPalette(colors: [0xfbfafb, 0x262f4c, 0xe82c5f, 0xf8c1ad]),
        ConfettiPalette(colors: [0xfcfefe, 0x5a1a5a, 0xec3c51, 0xfc9f2b]),
        ConfettiPalette(colors: [0xfd0094, 0x9cc835, 0xf5e9c8, 0xee7705]),
        ConfettiPalette(colors: [0xfdfffc, 0x273788, 0x3b76fc, 0xffaf09]),
        ConfettiPalette(colors: [0xeaa215, 0x1d181a, 0x3175ad, 0xdfd0b8]),
        ConfettiPalette(colors: [0x0f2647, 0x59dcfb, 0x9e7cfd, 0x9631f2]),
        ConfettiPalette(colors: [0x22b4a1, 0xff6262, 0xfaa534, 0xf7fac5]),
        ConfettiPalette(colors: [0xf83a63, 0x0bd5be, 0xfbfafa, 0x4f2e8c]),
        ConfettiPalette(colors: [0x006d56, 0xc7d800, 0xf9f9fb, 0x84ba32]),
        ConfettiPalette(colors: [0xe94459, 0x22c8b2, 0xf6d55e, 0x50032b]),
        ConfettiPalette(colors: [0x0c0f11, 0x96b78b, 0xbd9a5b, 0xb62a2b]),
        ConfettiPalette(colors: [0x275664, 0xf8af08, 0xe65f27, 0x2b2626]),
        ConfettiPalette(colors: [0xffe7db, 0x162e5b, 0x018577, 0x8be3dc]),
        ConfettiPalette(colors: [0xe84b5e, 0xf9db05, 0xfefffc, 0xffbe24]),
        ConfettiPalette(colors: [0x3564bd, 0xf6c81f, 0xf9fefd, 0x9fb0ff]),
        ConfettiPalette(colors: [0xf6fbfa, 0x47220d, 0xcd3e71, 0xada7a6]),
        ConfettiPalette(colors: [0xec1e45, 0xfce855, 0xf6fbf6, 0xfe7e99]),
        ConfettiPalette(colors: [0xfffdff, 0x5c3270, 0xcf2541, 0xcda0a1]),
        ConfettiPalette(colors: [0xfcfdfc, 0x203472, 0x276f9b, 0x0ab5d8]),
        ConfettiPalette(colors: [0xf8f8fb, 0x2b2727, 0x9f565b, 0xdea69a]),
        ConfettiPalette(colors: [0xf3f0db, 0x2e2c4c, 0xe73e25, 0xf7ae22]),
    ]

    /// sRGB relative luminance, 0 to 1.
    static func luminance(_ rgb: UInt32) -> Double {
        func linear(_ shift: UInt32) -> Double {
            let c = Double((rgb >> shift) & 0xFF) / 255.0
            return c < 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    /// Colors bright enough for the dark background. Falls back to all
    /// colors when fewer than 2 would remain.
    static func usable(_ p: ConfettiPalette) -> [UInt32] {
        let bright = p.colors.filter { luminance($0) >= 0.2 }
        return bright.count < 2 ? p.colors : bright
    }
}

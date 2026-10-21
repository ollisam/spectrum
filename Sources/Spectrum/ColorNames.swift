import Foundation

/// Finds the closest human-readable name for a color using CIEDE2000.
enum ColorNames {
    private struct Entry {
        let name: String
        let lab: Lab
    }

    private static let entries: [Entry] = table.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let rgb = RGB(hex: String(parts[0])) else { return nil }
        return Entry(name: String(parts[1]), lab: rgb.lab)
    }

    private static var cache: [RGB: String] = [:]

    static func name(for color: RGB) -> String {
        if let hit = cache[color] { return hit }
        let lab = color.lab
        var best = ""
        var bestDistance = Double.infinity
        for entry in entries {
            let d = lab.distance(to: entry.lab)
            if d < bestDistance {
                bestDistance = d
                best = entry.name
            }
        }
        if cache.count > 4096 { cache.removeAll(keepingCapacity: true) }
        cache[color] = best
        return best
    }

    private static let table = """
    000000 Black
    FFFFFF White
    808080 Gray
    C0C0C0 Silver
    A9A9A9 Dark Gray
    D3D3D3 Light Gray
    696969 Dim Gray
    DCDCDC Gainsboro
    F5F5F5 White Smoke
    36454F Charcoal
    1B1B1B Eerie Black
    242124 Raisin Black
    343434 Jet
    353839 Onyx
    2A3439 Gunmetal
    555D50 Ebony
    708090 Slate Gray
    778899 Light Slate Gray
    2F4F4F Dark Slate Gray
    E5E4E2 Platinum
    FAF9F6 Off White
    E3DAC9 Bone
    EAE0C8 Pearl
    FFFAFA Snow
    F0F8FF Alice Blue
    F8F8FF Ghost White
    F0FFFF Azure Mist
    F0FFF0 Honeydew
    F5FFFA Mint Cream
    FFFFF0 Ivory
    FFFAF0 Floral White
    FDF5E6 Old Lace
    FAF0E6 Linen
    FFF5EE Seashell
    FFF0F5 Lavender Blush
    FFFDD0 Cream
    F7E7CE Champagne
    F5F5DC Beige
    FAEBD7 Antique White
    FFEBCD Blanched Almond
    FFE4C4 Bisque
    FFEFD5 Papaya Whip
    FFE4B5 Moccasin
    FFDEAD Navajo White
    FFDAB9 Peach Puff
    FFE5B4 Peach
    FBCEB1 Apricot
    F5DEB3 Wheat
    FFF8DC Cornsilk
    FFFACD Lemon Chiffon
    FAFAD2 Light Goldenrod
    FFFFE0 Light Yellow
    EEE8AA Pale Goldenrod
    F0E68C Khaki
    BDB76B Dark Khaki
    C2B280 Sand
    D2B48C Tan
    DEB887 Burlywood
    F4A460 Sandy Brown
    BC8F8F Rosy Brown
    CD853F Peru
    D2691E Chocolate
    A0522D Sienna
    8B4513 Saddle Brown
    A52A2A Brown
    954535 Chestnut
    C04000 Mahogany
    6F4E37 Coffee
    483C32 Taupe
    B87333 Copper
    CD7F32 Bronze
    B7410E Rust
    E2725B Terracotta
    CB4154 Brick Red
    800000 Maroon
    800020 Burgundy
    722F37 Wine
    8B0000 Dark Red
    B22222 Firebrick
    DC143C Crimson
    FF0000 Red
    FF2400 Scarlet
    E34234 Vermilion
    DE3163 Cherry
    E0115F Ruby
    E30B5C Raspberry
    CD5C5C Indian Red
    F08080 Light Coral
    FA8072 Salmon
    E9967A Dark Salmon
    FFA07A Light Salmon
    FF7F50 Coral
    FF6347 Tomato
    FF4500 Orange Red
    FF8C00 Dark Orange
    FF7518 Pumpkin
    F28500 Tangerine
    FFA500 Orange
    FFBF00 Amber
    F4C430 Saffron
    FFD700 Gold
    DAA520 Goldenrod
    B8860B Dark Goldenrod
    FFDB58 Mustard
    FFF700 Lemon
    FFFF00 Yellow
    9ACD32 Yellow Green
    ADFF2F Green Yellow
    7FFF00 Chartreuse
    7CFC00 Lawn Green
    39FF14 Neon Green
    00FF00 Lime
    32CD32 Lime Green
    4CBB17 Kelly Green
    98FB98 Pale Green
    98FF98 Mint Green
    90EE90 Light Green
    00FA9A Medium Spring Green
    00FF7F Spring Green
    93E9BE Seafoam
    3EB489 Mint
    50C878 Emerald
    00A86B Jade
    3CB371 Medium Sea Green
    2E8B57 Sea Green
    228B22 Forest Green
    008000 Green
    006400 Dark Green
    355E3B Hunter Green
    01796F Pine Green
    9CAF88 Sage
    8FBC8F Dark Sea Green
    808000 Olive
    6B8E23 Olive Drab
    556B2F Dark Olive Green
    66CDAA Medium Aquamarine
    7FFFD4 Aquamarine
    20B2AA Light Sea Green
    008B8B Dark Cyan
    008080 Teal
    40E0D0 Turquoise
    48D1CC Medium Turquoise
    00CED1 Dark Turquoise
    AFEEEE Pale Turquoise
    00FFFF Cyan
    E0FFFF Light Cyan
    7DF9FF Electric Blue
    B0E0E6 Powder Blue
    ADD8E6 Light Blue
    89CFF0 Baby Blue
    87CEEB Sky Blue
    87CEFA Light Sky Blue
    00BFFF Deep Sky Blue
    007BA7 Cerulean
    1E90FF Dodger Blue
    007FFF Azure
    6495ED Cornflower Blue
    4682B4 Steel Blue
    B0C4DE Light Steel Blue
    5F9EA0 Cadet Blue
    1560BD Denim
    4169E1 Royal Blue
    0047AB Cobalt
    0F52BA Sapphire
    0000FF Blue
    0000CD Medium Blue
    00008B Dark Blue
    000080 Navy
    191970 Midnight Blue
    120A8F Ultramarine
    CCCCFF Periwinkle
    E6E6FA Lavender
    6A5ACD Slate Blue
    483D8B Dark Slate Blue
    7B68EE Medium Slate Blue
    9370DB Medium Purple
    663399 Rebecca Purple
    9966CC Amethyst
    8A2BE2 Blue Violet
    4B0082 Indigo
    9400D3 Dark Violet
    9932CC Dark Orchid
    BA55D3 Medium Orchid
    800080 Purple
    8B008B Dark Magenta
    614051 Eggplant
    C8A2C8 Lilac
    E0B0FF Mauve
    D8BFD8 Thistle
    DDA0DD Plum
    EE82EE Violet
    DA70D6 Orchid
    FF00FF Magenta
    C71585 Medium Violet Red
    FF1493 Deep Pink
    FF007F Rose
    FF69B4 Hot Pink
    DE5D83 Blush
    DB7093 Pale Violet Red
    FFC1CC Bubblegum
    FFC0CB Pink
    FFB6C1 Light Pink
    FFE4E1 Misty Rose
    """
}

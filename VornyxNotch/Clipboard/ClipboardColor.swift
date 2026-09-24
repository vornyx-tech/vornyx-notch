//
//  ClipboardColor.swift
//  VornyxNotch
//
//  Recognises a colour in a copy, whatever notation it is written in.
//

import Foundation

/// A colour, as 0...1 components.
struct ClipboardColor: Equatable {
    let red: Double, green: Double, blue: Double, alpha: Double

    var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /// The whole copy as a colour - hex, rgb(), hsl(), or a Swift or
    /// Objective-C colour initialiser - or nil if it is anything else.
    static func parse(_ text: String) -> ClipboardColor? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 80 else { return nil }
        return hex(s) ?? css(s) ?? initialiser(s)
    }

    // MARK: - #RGB, #RGBA, #RRGGBB, #RRGGBBAA, 0xRRGGBB

    private static func hex(_ s: String) -> ClipboardColor? {
        var digits: Substring
        if s.hasPrefix("#") { digits = s.dropFirst() }
        else if s.lowercased().hasPrefix("0x") { digits = s.dropFirst(2) }
        else { return nil }
        guard digits.allSatisfy(\.isHexDigit), [3, 4, 6, 8].contains(digits.count) else { return nil }
        if digits.count <= 4 { digits = Substring(digits.map { "\($0)\($0)" }.joined()) }
        guard let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let shift = hasAlpha ? 8 : 0
        return ClipboardColor(
            red: Double((value >> (16 + shift)) & 0xFF) / 255,
            green: Double((value >> (8 + shift)) & 0xFF) / 255,
            blue: Double((value >> shift) & 0xFF) / 255,
            alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1)
    }

    // MARK: - rgb(), rgba(), hsl(), hsla()

    private static func css(_ s: String) -> ClipboardColor? {
        let lower = s.lowercased().replacingOccurrences(of: ";", with: "")
        guard let open = lower.firstIndex(of: "("), lower.hasSuffix(")") else { return nil }
        let function = String(lower[..<open]).trimmingCharacters(in: .whitespaces)
        let inside = lower[lower.index(after: open)..<lower.index(before: lower.endIndex)]
        // Commas, spaces and the slash before alpha all separate.
        let parts = inside.split(whereSeparator: { ", /".contains($0) }).map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }

        func number(_ part: String, full: Double) -> Double? {
            if part.hasSuffix("%") { return Double(part.dropLast()).map { $0 / 100 * full } }
            return Double(part.replacingOccurrences(of: "deg", with: ""))
        }
        let alpha = parts.count == 4 ? number(parts[3], full: 1) : 1

        switch function {
        case "rgb", "rgba":
            guard let r = number(parts[0], full: 255), let g = number(parts[1], full: 255),
                  let b = number(parts[2], full: 255), let alpha,
                  [r, g, b].allSatisfy({ (0...255).contains($0) })
            else { return nil }
            return ClipboardColor(red: r / 255, green: g / 255, blue: b / 255, alpha: min(1, max(0, alpha)))
        case "hsl", "hsla":
            guard let h = number(parts[0], full: 360), let sat = number(parts[1], full: 1),
                  let light = number(parts[2], full: 1), let alpha,
                  parts[1].hasSuffix("%"), parts[2].hasSuffix("%")
            else { return nil }
            return fromHSL(h: h, s: sat, l: light, alpha: min(1, max(0, alpha)))
        default:
            return nil
        }
    }

    private static func fromHSL(h: Double, s: Double, l: Double, alpha: Double) -> ClipboardColor {
        let c = (1 - abs(2 * l - 1)) * s
        let hue = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch hue {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        return ClipboardColor(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }

    // MARK: - Color(red:green:blue:), UIColor, NSColor, CGColor

    private static func initialiser(_ s: String) -> ClipboardColor? {
        let names = ["Color(", "UIColor(", "NSColor(", "CGColor(", ".init("]
        guard names.contains(where: s.contains), s.hasSuffix(")") else { return nil }

        func component(_ label: String) -> Double? {
            guard let range = s.range(of: "\(label):") else { return nil }
            let rest = s[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let expression = rest.prefix { "0123456789./ ".contains($0) }
                .trimmingCharacters(in: .whitespaces)
            // 0.5, or 128/255 and 128.0 / 255.0.
            let sides = expression.split(separator: "/").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            if sides.count == 2, let a = sides[0], let b = sides[1], b != 0 { return a / b }
            return sides.first.flatMap { $0 }
        }
        guard let r = component("red"), let g = component("green"), let b = component("blue"),
              [r, g, b].allSatisfy({ (0...1).contains($0) })
        else { return nil }
        return ClipboardColor(red: r, green: g, blue: b, alpha: min(1, max(0, component("alpha") ?? 1)))
    }
}

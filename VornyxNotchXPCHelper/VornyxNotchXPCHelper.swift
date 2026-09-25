//
//  VornyxNotchXPCHelper.swift
//  VornyxNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics
import AppKit
import OSLog

class VornyxNotchXPCHelper: NSObject, VornyxNotchXPCHelperProtocol {
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - Focus

    /// Whether Control Center has its Focus item in the menu bar.
    ///
    /// Stands in for `INFocusStatusCenter`, which answers only apps signed with
    /// the Communication Notifications capability. With Focus set to show in
    /// the menu bar "When Active", the item exists exactly while a Focus is on.
    ///
    /// Replies with a `FocusProbe` raw value rather than a bare yes or no, so
    /// the app can say which of the requirements is missing.
    @objc func isFocusMenuExtraShowing(with reply: @escaping (NSNumber?) -> Void) {
        let probe = probeFocus()
        logFocusProbe(probe)
        reply(NSNumber(value: probe.rawValue))
    }

    /// The active Focus, from `~/Library/DoNotDisturb/DB/Assertions.json` -
    /// the file macOS itself writes as a Focus goes on and off, and the one
    /// source that also says which Focus. It sits behind Full Disk Access,
    /// which the helper can use because it is not sandboxed and inherits the
    /// app's grant.
    ///
    /// Approach from DynamicNotch by Evgeniy Petrukovich (GPL-3.0).
    @objc func focusAssertionState(with reply: @escaping (NSString?) -> Void) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: url) else { return reply("unreadable") }

        struct Root: Decodable { let data: [Entry] }
        struct Entry: Decodable { let storeAssertionRecords: [Record]? }
        struct Record: Decodable { let assertionDetails: Details? }
        struct Details: Decodable { let assertionDetailsModeIdentifier: String? }

        // macOS cuts the file down to a stub with no Focus on, which does not
        // decode: that is off, not unreadable.
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return reply("off") }
        let mode = root.data
            .flatMap { $0.storeAssertionRecords ?? [] }
            .compactMap { $0.assertionDetails?.assertionDetailsModeIdentifier }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        reply((mode ?? "off") as NSString)
    }

    // MARK: - VPN

    /// The first connected VPN service `scutil --nc list` knows - every VPN
    /// macOS manages, WireGuard and other Network Extension ones included -
    /// and when it connected, from `scutil --nc status`.
    ///
    /// Approach from DynamicNotch by Evgeniy Petrukovich (GPL-3.0).
    @objc func connectedVPN(with reply: @escaping (NSDictionary?) -> Void) {
        guard let list = Self.run("/usr/sbin/scutil", ["--nc", "list"]) else { return reply(nil) }

        // * (Connected)   0411615F-... VPN (com.wireguard.macos) "vania-tunnel"   [VPN:com.wireguard.macos]
        guard let line = list.split(separator: "\n").first(where: { $0.contains("(Connected)") }),
              let uuidRange = line.range(
                of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
                options: .regularExpression)
        else { return reply(nil) }

        let uuid = String(line[uuidRange])
        let rest = line[uuidRange.upperBound...]
        var info: [String: Any] = ["id": uuid]

        if let open = rest.firstIndex(of: "\""),
           let close = rest[rest.index(after: open)...].firstIndex(of: "\"") {
            info["name"] = String(rest[rest.index(after: open)..<close])
        }
        if let open = rest.firstIndex(of: "("), let close = rest.firstIndex(of: ")"), open < close {
            let inside = rest[rest.index(after: open)..<close]
            if inside.contains(".") { info["bundleID"] = String(inside) }
        }

        if let status = Self.run("/usr/sbin/scutil", ["--nc", "status", uuid]),
           let line = status.split(separator: "\n").first(where: { $0.contains("LastStatusChangeTime") }),
           let value = line.split(separator: ":", maxSplits: 1).last {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
            if let date = formatter.date(from: value.trimmingCharacters(in: .whitespaces)) {
                info["connectedAt"] = date.timeIntervalSince1970
            }
        }
        reply(info as NSDictionary)
    }

    /// A command's standard output, or nil if it could not run.
    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    @objc func focusMenuExtraTitle(with reply: @escaping (NSString?) -> Void) {
        guard AXIsProcessTrusted(),
              let controlCenter = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.controlcenter").first
        else { return reply(nil) }
        let app = AXUIElementCreateApplication(controlCenter.processIdentifier)
        var extras: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &extras) == .success,
              let bar = extras, CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return reply(nil) }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(bar as! AXUIElement, "AXChildren" as CFString, &children)
        for item in children as? [AXUIElement] ?? [] {
            let texts = ["AXIdentifier", "AXDescription", "AXTitle", "AXValue", "AXHelp"].compactMap { attribute -> String? in
                var value: CFTypeRef?
                AXUIElementCopyAttributeValue(item, attribute as CFString, &value)
                return value as? String
            }
            guard texts.contains(where: { $0.localizedCaseInsensitiveContains("focus") }) else { continue }
            return reply(texts.joined(separator: " ") as NSString)
        }
        reply(nil)
    }

    private enum FocusProbe: Int {
        case off = 0
        case on = 1
        case noAccessibility = 2
        case noMenuBar = 3
    }

    private func probeFocus() -> FocusProbe {
        guard AXIsProcessTrusted() else { return .noAccessibility }
        guard let controlCenter = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.controlcenter").first
        else { return .noMenuBar }

        let app = AXUIElementCreateApplication(controlCenter.processIdentifier)
        var extras: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &extras) == .success,
              let bar = extras, CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return .noMenuBar }

        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(bar as! AXUIElement, "AXChildren" as CFString, &children)
        let names = (children as? [AXUIElement] ?? []).map { item -> String in
            // The identifier is what matters; the description is a fallback
            // for releases that leave it empty.
            ["AXIdentifier", "AXDescription"].compactMap { attribute -> String? in
                var value: CFTypeRef?
                AXUIElementCopyAttributeValue(item, attribute as CFString, &value)
                return value as? String
            }.joined(separator: " ")
        }
        logMenuExtras(names)
        let focused = names.contains {
            $0.localizedCaseInsensitiveContains("focus")
                || $0.localizedCaseInsensitiveContains("do not disturb")
        }
        return focused ? .on : .off
    }

    /// Public, so what the helper reads shows in Console as text rather than
    /// `<private>`, the way NSLog does.
    private let focusLog = Logger(subsystem: "tech.vornyx.notch", category: "Focus")
    private let menuExtrasLock = NSLock()
    private var loggedMenuExtras: [String]?
    private var loggedProbe: FocusProbe?

    /// Logged on change only, so the identifiers can be checked in Console
    /// without a line every second.
    private func logMenuExtras(_ identifiers: [String]) {
        menuExtrasLock.lock()
        defer { menuExtrasLock.unlock() }
        guard identifiers != loggedMenuExtras else { return }
        loggedMenuExtras = identifiers
        focusLog.notice("menu extras: \(identifiers.joined(separator: ", "), privacy: .public)")
    }

    private func logFocusProbe(_ probe: FocusProbe) {
        menuExtrasLock.lock()
        defer { menuExtrasLock.unlock() }
        guard probe != loggedProbe else { return }
        loggedProbe = probe
        focusLog.notice("probe: \(String(describing: probe), privacy: .public)")
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}

//
//  VornyxNotchXPCHelperProtocol.swift
//  VornyxNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol VornyxNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Focus, read from Control Center's menu bar item (performed by the helper)
    func isFocusMenuExtraShowing(with reply: @escaping (NSNumber?) -> Void)
    // Focus, read from the file macOS writes it to; needs Full Disk Access.
    // "unreadable", "off", or the active mode's identifier.
    func focusAssertionState(with reply: @escaping (NSString?) -> Void)
    // What Control Center's Focus item calls itself - "Focus, Work" - for
    // telling the mode apart without Full Disk Access. Nil if not showing.
    func focusMenuExtraTitle(with reply: @escaping (NSString?) -> Void)
    // The connected VPN, from scutil: name, bundleID, connectedAt (seconds
    // since 1970). Nil when none is connected.
    func connectedVPN(with reply: @escaping (NSDictionary?) -> Void)
    // Stops a screenshot-toolbar recording: SIGINT to screencapture, as its
    // own stop button does.
    func stopScreenCapture()
}

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     connectionToService = NSXPCConnection(serviceName: "tech.vornyx.notch.VornyxNotchXPCHelper")
     connectionToService.remoteObjectInterface = NSXPCInterface(with: (any VornyxNotchXPCHelperProtocol).self)
     connectionToService.resume()

 Once you have a connection to the service, you can use it like this:

     if let proxy = connectionToService.remoteObjectProxy as? VornyxNotchXPCHelperProtocol {
         proxy.performCalculation(firstNumber: 23, secondNumber: 19) { result in
             NSLog("Result of calculation is: \(result)")
         }
     }

 And, when you are finished with the service, clean up the connection like this:

     connectionToService.invalidate()
*/

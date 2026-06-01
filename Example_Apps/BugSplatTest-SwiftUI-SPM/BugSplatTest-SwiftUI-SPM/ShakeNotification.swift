//
//  ShakeNotification.swift
//  BugSplatTest-SwiftUI-SPM
//
//  Bridge for forwarding device-shake events to SwiftUI views, which don't
//  otherwise get a motion-event hook. We embed a tiny first-responder
//  UIViewController via UIViewControllerRepresentable; it overrides
//  motionEnded(_:with:) and calls back on shake.
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI
import UIKit

/// Zero-size SwiftUI view that becomes first responder so it can receive
/// device-motion events. Pair with `.background(ShakeDetector { ... })` on
/// any view that wants to react to a shake.
struct ShakeDetector: UIViewControllerRepresentable {
    let onShake: () -> Void

    final class ResponderViewController: UIViewController {
        var onShake: (() -> Void)?
        override var canBecomeFirstResponder: Bool { true }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }
        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            super.motionEnded(motion, with: event)
            if motion == .motionShake { onShake?() }
        }
    }

    func makeUIViewController(context: Context) -> ResponderViewController {
        let vc = ResponderViewController()
        vc.onShake = onShake
        return vc
    }

    func updateUIViewController(_ vc: ResponderViewController, context: Context) {
        vc.onShake = onShake
    }
}

//
//  NDIFrameConsumer.swift
//  NDIReceiverExample
//
//  Created by Ed on 04.02.26.
//

import NDIKit

/// Receives NDI video frames for rendering.
protocol NDIFrameConsumer: AnyObject, Sendable {
    nonisolated func enqueue(_ frame: NDIVideoFrame)
    func drain() async
}

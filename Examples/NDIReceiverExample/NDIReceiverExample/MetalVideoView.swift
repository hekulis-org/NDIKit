//
//  MetalVideoView.swift
//  NDIReceiverExample
//
//  Created by Ed on 04.02.26.
//

import MetalKit
import SwiftUI

struct MetalVideoView: NSViewRepresentable {
    let viewModel: NDIReceiverViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.update(viewModel: viewModel)
    }

    @MainActor
    final class Coordinator {
        private weak var viewModel: NDIReceiverViewModel?
        private var renderer: MetalVideoRenderer?
        private weak var view: MTKView?

        init(viewModel: NDIReceiverViewModel) {
            self.viewModel = viewModel
        }

        func attach(to view: MTKView) {
            self.view = view

            if let renderer = MetalVideoRenderer(view: view) {
                self.renderer = renderer
                view.delegate = renderer
                viewModel?.setFrameConsumer(renderer)
            } else {
                viewModel?.setErrorMessage("Metal 4 GPU required to render video.")
            }
        }

        func update(viewModel: NDIReceiverViewModel) {
            if self.viewModel !== viewModel {
                self.viewModel?.setFrameConsumer(nil)
                self.viewModel = viewModel
                if let renderer {
                    viewModel.setFrameConsumer(renderer)
                }
            }
        }

        deinit {
            viewModel?.setFrameConsumer(nil)
        }
    }
}

//
//  MetalCameraView.swift
//  NDISenderExample
//

import MetalKit
import SwiftUI

/// A SwiftUI wrapper around `MTKView` that displays the camera preview.
///
/// Creates a ``CameraPipeline`` when the view is first attached and wires
/// it to the ``CameraSenderViewModel``.
struct MetalCameraView: UIViewRepresentable {
    let viewModel: CameraSenderViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(viewModel: viewModel)
    }

    /// Bridges the SwiftUI lifecycle to the Metal pipeline.
    @MainActor
    final class Coordinator {
        private weak var viewModel: CameraSenderViewModel?
        private var pipeline: CameraPipeline?
        private weak var view: MTKView?

        init(viewModel: CameraSenderViewModel) {
            self.viewModel = viewModel
        }

        /// Creates the pipeline and sets it as the view's delegate.
        func attach(to view: MTKView) {
            self.view = view

            if let pipeline = CameraPipeline(view: view) {
                self.pipeline = pipeline
                view.delegate = pipeline.renderer
                viewModel?.setPipeline(pipeline)
            } else {
                viewModel?.setPipeline(nil)
                viewModel?.setErrorMessage("Failed to initialize Metal renderer.")
            }
        }

        /// Re-wires the pipeline when SwiftUI provides a new view model identity.
        func update(viewModel: CameraSenderViewModel) {
            if self.viewModel !== viewModel {
                self.viewModel = viewModel
                viewModel.setPipeline(pipeline)
            }
        }
    }
}

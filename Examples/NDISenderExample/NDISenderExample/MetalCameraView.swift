//
//  MetalCameraView.swift
//  NDISenderExample
//
//  Created by Ed on 04.02.26.
//

import MetalKit
import SwiftUI

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

    @MainActor
    final class Coordinator {
        private weak var viewModel: CameraSenderViewModel?
        private var renderer: CameraSenderRenderer?
        private weak var view: MTKView?

        init(viewModel: CameraSenderViewModel) {
            self.viewModel = viewModel
        }

        func attach(to view: MTKView) {
            self.view = view

            if let renderer = CameraSenderRenderer(view: view) {
                self.renderer = renderer
                view.delegate = renderer
                viewModel?.setRenderer(renderer)
            } else {
                viewModel?.setRenderer(nil)
                viewModel?.setErrorMessage("Metal 4 GPU required to stream video.")
            }
        }

        func update(viewModel: CameraSenderViewModel) {
            if self.viewModel !== viewModel {
                self.viewModel = viewModel
                viewModel.setRenderer(renderer)
            }
        }
    }
}

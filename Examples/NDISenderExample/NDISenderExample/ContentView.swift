//
//  ContentView.swift
//  NDISenderExample
//
//  Created by Ed on 04.02.26.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = CameraSenderViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        let groupsBinding = Binding(
            get: { viewModel.configuration.groups ?? "" },
            set: { viewModel.configuration.groups = $0.isEmpty ? nil : $0 }
        )

        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.black)

                        MetalCameraView(viewModel: viewModel)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                        if !viewModel.isStreaming {
                            VStack(spacing: 8) {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        if let error = viewModel.errorMessage {
                            VStack {
                                Spacer()
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                    Text(error)
                                        .foregroundStyle(.white)
                                }
                                .padding(10)
                                .background(.red.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(12)
                            }
                        }
                    }
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 16) {
                        // Camera Settings Section
                        Text("Camera Settings")
                            .font(.headline)

                        VStack(spacing: 12) {
                            // Camera Selection
                            HStack {
                                Text("Camera")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Picker("Camera", selection: $viewModel.configuration.selectedCameraID) {
                                    ForEach(viewModel.availableCameras) { camera in
                                        Text(camera.name).tag(camera.id as String?)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            .padding(10)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            // Resolution Selection
                            HStack {
                                Text("Resolution")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Picker("Resolution", selection: $viewModel.configuration.resolution) {
                                    ForEach(VideoResolution.allCases) { resolution in
                                        Text(resolution.rawValue).tag(resolution)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            .padding(10)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            // Frame Rate Selection
                            HStack {
                                Text("Frame Rate")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Picker("Frame Rate", selection: $viewModel.configuration.frameRate) {
                                    ForEach(VideoFrameRate.allCases) { fps in
                                        Text(fps.displayName).tag(fps)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            .padding(10)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(viewModel.isStreaming)

                        // NDI Settings Section
                        Text("NDI Settings")
                            .font(.headline)
                            .padding(.top, 8)

                        VStack(spacing: 12) {
                            TextField("Sender Name", text: $viewModel.configuration.senderName)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .padding(10)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            TextField("Groups (optional)", text: groupsBinding)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .padding(10)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            Toggle("Clock Video", isOn: $viewModel.configuration.clockVideo)
                            Toggle("Clock Audio", isOn: $viewModel.configuration.clockAudio)
                        }
                        .disabled(viewModel.isStreaming)

                        Button {
                            if viewModel.isStreaming {
                                viewModel.stopStreaming()
                            } else {
                                viewModel.startStreaming()
                            }
                        } label: {
                            Text(viewModel.isStreaming ? "Stop Streaming" : "Start Streaming")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.isStreaming ? .red : .green)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("NDI Sender")
            .onDisappear {
                viewModel.stopStreaming()
            }
        }
    }
}

#Preview {
    ContentView()
}

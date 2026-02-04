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
                        Text("Sender Settings")
                            .font(.headline)

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

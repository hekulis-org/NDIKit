//
//  ContentView.swift
//  NDIReceiverExample
//
//  Created by Ed on 04.02.26.
//

import SwiftUI
import NDIKit

struct ContentView: View {
    @State private var viewModel = NDIReceiverViewModel()

    var body: some View {
        NavigationSplitView {
            SourceListView(viewModel: viewModel)
        } detail: {
            VideoView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.startDiscovery()
        }
        .onDisappear {
            viewModel.stopDiscovery()
            viewModel.disconnect()
        }
    }
}

// MARK: - Source List View

struct SourceListView: View {
    @Bindable var viewModel: NDIReceiverViewModel

    var body: some View {
        List(selection: $viewModel.selectedSource) {
            Section("NDI Sources") {
                if viewModel.sources.isEmpty {
                    Text("Searching for sources...")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(viewModel.sources) { source in
                        SourceRow(source: source, isSelected: viewModel.selectedSource == source)
                            .tag(source)
                    }
                }
            }
        }
        .navigationTitle("Sources")
        .toolbar {
            ToolbarItem {
                if viewModel.isConnected {
                    Button("Disconnect") {
                        viewModel.selectedSource = nil
                    }
                }
            }
        }
    }
}

struct SourceRow: View {
    let source: NDISource
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "video.fill" : "video")
                .foregroundStyle(isSelected ? .green : .secondary)
            Text(source.name)
        }
    }
}

// MARK: - Video View

struct VideoView: View {
    let viewModel: NDIReceiverViewModel

    var body: some View {
        ZStack {
            Color.black

            if let frame = viewModel.currentFrame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if viewModel.selectedSource != nil {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Connecting...")
                        .foregroundStyle(.white)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("Select an NDI source to begin")
                        .foregroundStyle(.secondary)
                }
            }

            // Frame info overlay
            if let info = viewModel.frameInfo {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FrameInfoOverlay(info: info)
                            .padding()
                    }
                }
            }

            // Error overlay
            if let error = viewModel.errorMessage {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .foregroundStyle(.white)
                    }
                    .padding()
                    .background(.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
                }
            }
        }
    }
}

struct FrameInfoOverlay: View {
    let info: NDIReceiverViewModel.FrameInfo

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(info.width) × \(info.height)")
            Text(String(format: "%.2f fps", info.frameRate))
            Text(info.formatDescription)
        }
        .font(.caption.monospaced())
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    ContentView()
}

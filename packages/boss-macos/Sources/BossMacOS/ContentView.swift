import libboss
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: BossMacOSViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detail
        }
        .task {
            viewModel.refreshIfNeeded()
        }
        .sheet(isPresented: $viewModel.isPresentingSaveProfilePrompt) {
            SaveCustomProfileSheet(viewModel: viewModel)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bose QC Ultra 2 HP")
                    .font(.title2)
                    .fontWeight(.semibold)

                statusView
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Connection")
                    .font(.headline)

                TextField("Name contains", text: $viewModel.nameFilter)
                    .textFieldStyle(.roundedBorder)

                Stepper(value: $viewModel.scanTimeoutSeconds, in: 5...60, step: 5) {
                    Text("Scan timeout: \(viewModel.scanTimeoutSeconds)s")
                }

                Button {
                    viewModel.refresh()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
            }

            if !viewModel.visibleSidebarModes.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Mode")
                        .font(.headline)

                    ForEach(viewModel.visibleSidebarModes, id: \.modeIndex) { mode in
                        HStack(spacing: 8) {
                            Button {
                                viewModel.selectAudioMode(mode.modeIndex)
                            } label: {
                                HStack {
                                    Text(viewModel.customProfileDisplayName(for: mode))
                                    Spacer()
                                    if viewModel.displayedCurrentAudioModeIndex == mode.modeIndex {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isBusy)

                            Button {
                                viewModel.setFavorite(!mode.favorite, for: mode)
                            } label: {
                                Image(systemName: mode.favorite ? "star.fill" : "star")
                                    .foregroundStyle(mode.favorite ? .yellow : .secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isBusy)

                            if viewModel.canDelete(mode) {
                                Button {
                                    viewModel.deleteCustomProfile(mode)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isBusy)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Controls")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Text("Current mode: \(viewModel.selectedModeName)")
                    .foregroundStyle(.secondary)
            }

            SettingsPanel(viewModel: viewModel)

            Spacer()
        }
        .padding(28)
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.loadState {
        case .idle:
            Label("Waiting to scan", systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
        case .loading(let label):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(label)
            }
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .ready:
            Label(viewModel.lastResultMessage ?? "Connected", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        }
    }
}

private struct SettingsPanel: View {
    @ObservedObject var viewModel: BossMacOSViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Audio Settings")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                if viewModel.canSaveCustomProfile {
                    Button {
                        viewModel.beginSavingCustomProfile()
                    } label: {
                        Label("Save as Custom Profile", systemImage: "square.and.arrow.down")
                    }
                }

                Button {
                    viewModel.applySettings()
                } label: {
                    Label("Apply", systemImage: "checkmark")
                }
                .disabled(!viewModel.canApplySettings)
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                GridRow {
                    Text("CNC")
                        .foregroundStyle(.secondary)
                    HStack {
                        Slider(value: cncBinding, in: 0...10, step: 1)
                        Text("\(viewModel.cncLevel)")
                            .monospacedDigit()
                            .frame(width: 24, alignment: .trailing)
                    }
                }

                GridRow {
                    Text("Spatial Audio")
                        .foregroundStyle(.secondary)
                    Picker("Spatial Audio", selection: spatialAudioBinding) {
                        ForEach(BossSpatialAudioMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                GridRow {
                    Text("Wind Block")
                        .foregroundStyle(.secondary)
                    Toggle("Enabled", isOn: windBlockBinding)
                }

                GridRow {
                    Text("ANC Toggle")
                        .foregroundStyle(.secondary)
                    Toggle("Enabled", isOn: ancBinding)
                }
            }
            .disabled(viewModel.settings == nil || viewModel.isBusy)

            if viewModel.settings == nil {
                ContentUnavailableView(
                    "No Settings Loaded",
                    systemImage: "slider.horizontal.3",
                    description: Text("Refresh to connect and read the current headset settings.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .padding(20)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }

    private var cncBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.cncLevel) },
            set: { viewModel.setCNCLevelDraft(Int($0.rounded())) }
        )
    }

    private var spatialAudioBinding: Binding<BossSpatialAudioMode> {
        Binding(
            get: { viewModel.spatialAudioMode },
            set: { viewModel.setSpatialAudioModeDraft($0) }
        )
    }

    private var windBlockBinding: Binding<Bool> {
        Binding(
            get: { viewModel.windBlockEnabled },
            set: { viewModel.setWindBlockEnabledDraft($0) }
        )
    }

    private var ancBinding: Binding<Bool> {
        Binding(
            get: { viewModel.ancToggleEnabled },
            set: { viewModel.setANCEnabledDraft($0) }
        )
    }
}

private struct SaveCustomProfileSheet: View {
    @ObservedObject var viewModel: BossMacOSViewModel
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Save Custom Profile")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Profile name", text: $viewModel.pendingProfileName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFieldFocused)
                .onSubmit {
                    viewModel.confirmSavingCustomProfile()
                }

            Picker("Hardware Prompt", selection: $viewModel.selectedSaveProfilePromptName) {
                ForEach(viewModel.selectableSaveProfilePrompts, id: \.name) { prompt in
                    Text(prompt.name).tag(prompt.name)
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    viewModel.cancelSavingCustomProfile()
                }

                Button("Save") {
                    viewModel.confirmSavingCustomProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.pendingProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .task {
            AppDelegate.activateApp()
            isNameFieldFocused = true
        }
    }
}

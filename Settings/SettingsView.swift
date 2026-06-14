import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var cameraService: CameraService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection("General", systemImage: "slider.horizontal.3") {
                Toggle("Show on all Spaces", isOn: $settingsStore.showOnAllSpaces)
                Toggle("Remember last window position", isOn: $settingsStore.rememberWindowPosition)
                Toggle("Remember last window size", isOn: $settingsStore.rememberWindowSize)
            }

            SettingsDivider()

            SettingsSection("Window", systemImage: "macwindow") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Rounded corner radius")
                        Spacer()
                        Text("\(Int(settingsStore.roundedCornerRadius)) px")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $settingsStore.roundedCornerRadius,
                        in: 0...80,
                        step: 1
                    )
                }

                Toggle("Window shadow", isOn: $settingsStore.windowShadow)
            }

            SettingsDivider()

            SettingsSection("Camera", systemImage: "person.crop.rectangle") {
                Toggle("Mirror camera", isOn: $settingsStore.mirrorCamera)

                Picker("Camera device", selection: $settingsStore.selectedCameraUniqueID) {
                    Text("System Default").tag("")

                    ForEach(cameraService.availableVideoDevices) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }

                    if shouldShowUnavailableSelectedCamera {
                        Text("Selected camera unavailable").tag(settingsStore.selectedCameraUniqueID)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    cameraService.refreshAvailableVideoDevices()
                } label: {
                    Label("Refresh Cameras", systemImage: "arrow.clockwise")
                }
            }

            SettingsDivider()

            SettingsSection("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right") {
                Picker("Keyboard shortcut", selection: $settingsStore.fullscreenShortcut) {
                    ForEach(FullscreenKeyboardShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Escape exits fullscreen", isOn: $settingsStore.escapeExitsFullscreen)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .background(SettingsWindowConfigurator())
        .onAppear {
            cameraService.refreshAvailableVideoDevices()
        }
    }

    private var shouldShowUnavailableSelectedCamera: Bool {
        guard !settingsStore.selectedCameraUniqueID.isEmpty else {
            return false
        }

        return !cameraService.availableVideoDevices.contains {
            $0.uniqueID == settingsStore.selectedCameraUniqueID
        }
    }
}

private struct SettingsSection<Content: View>: View {
    private let title: String
    private let systemImage: String
    private let content: Content

    init(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 22)
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWhenAttached(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWhenAttached(nsView)
    }

    private func configureWhenAttached(_ view: NSView) {
        DispatchQueue.main.async {
            configure(window: view.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.title = "WindowPane Settings"
        window.titleVisibility = .visible
        window.toolbar = nil
        window.toolbarStyle = .automatic
    }
}

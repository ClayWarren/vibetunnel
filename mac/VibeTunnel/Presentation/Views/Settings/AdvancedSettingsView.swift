import AppKit
import OSLog
import SwiftUI

// MARK: - Logger

extension Logger {
    fileprivate static let advanced = Logger(subsystem: "com.vibetunnel.VibeTunnel", category: "AdvancedSettings")
}

/// Advanced settings tab for power user options
struct AdvancedSettingsView: View {
    @AppStorage("debugMode")
    private var debugMode = false
    @AppStorage("cleanupOnStartup")
    private var cleanupOnStartup = true
    @AppStorage("showInDock")
    private var showInDock = false
    @State private var cliInstaller = CLIInstaller()
    @State private var showingVtConflictAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // Apps preference section
                TerminalPreferenceSection()

                // Integration section
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Install CLI Tool")
                            Spacer()
                            ZStack {
                                // Hidden button to maintain consistent height
                                Button("Placeholder") {}
                                    .buttonStyle(.bordered)
                                    .opacity(0)
                                    .allowsHitTesting(false)

                                // Actual content
                                if cliInstaller.isInstalled {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("VT installed")
                                            .foregroundColor(.secondary)

                                        // Show reinstall button in debug mode
                                        if debugMode {
                                            Button(action: {
                                                cliInstaller.installCLITool()
                                            }, label: {
                                                Image(systemName: "arrow.clockwise.circle")
                                                    .font(.system(size: 14))
                                            })
                                            .buttonStyle(.plain)
                                            .foregroundColor(.accentColor)
                                            .help("Reinstall CLI tool")
                                        }
                                    }
                                } else {
                                    Button("Install 'vt' Command") {
                                        Task {
                                            await cliInstaller.install()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(cliInstaller.isInstalling)
                                }
                            }
                        }

                        if let error = cliInstaller.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            HStack(alignment: .center, spacing: 8) {
                                if cliInstaller.isInstalled {
                                    Text("The 'vt' command line tool is installed at /usr/local/bin/vt")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Install the 'vt' command line tool to /usr/local/bin for terminal access.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button(action: {
                                    showingVtConflictAlert = true
                                }, label: {
                                    Text("Use a different name")
                                        .font(.caption)
                                })
                                .buttonStyle(.link)
                            }
                        }
                    }
                } header: {
                    Text("Integration")
                        .font(.headline)
                } footer: {
                    Text(
                        "Prefix any terminal command with 'vt' to enable remote control."
                    )
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                }

                // Advanced section
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Clean up old sessions on startup", isOn: $cleanupOnStartup)
                        Text("Automatically remove terminated sessions when the app starts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Show in Dock
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Show in Dock", isOn: showInDockBinding)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show VibeTunnel icon in the Dock.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("The dock icon is always displayed when the Settings dialog is visible.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Debug mode toggle
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Debug mode", isOn: $debugMode)
                        Text("Enable additional logging and debugging features.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Advanced")
                        .font(.headline)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Advanced Settings")
        }
        .onAppear {
            cliInstaller.checkInstallationStatus()
        }
        .alert("Using a Different Command Name", isPresented: $showingVtConflictAlert) {
            Button("OK") {}
            Button("Copy to Clipboard") {
                copyCommandToClipboard()
            }
        } message: {
            Text(vtConflictMessage)
        }
    }

    private var showInDockBinding: Binding<Bool> {
        Binding(
            get: { showInDock },
            set: { newValue in
                showInDock = newValue
                // Don't change activation policy while settings window is open
                // The change will be applied when the settings window closes
            }
        )
    }

    private var vtScriptPath: String {
        if let path = Bundle.main.path(forResource: "vt", ofType: nil) {
            return path
        }
        return "/Applications/VibeTunnel.app/Contents/Resources/vt"
    }

    private var vtConflictMessage: String {
        """
        You can install the `vt` bash script with a different name. For example:

        cp "\(vtScriptPath)" /usr/local/bin/vtunnel && chmod +x /usr/local/bin/vtunnel
        """
    }

    private func copyCommandToClipboard() {
        let command = "cp \"\(vtScriptPath)\" /usr/local/bin/vtunnel && chmod +x /usr/local/bin/vtunnel"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
    }
}

// MARK: - Terminal Preference Section

private struct TerminalPreferenceSection: View {
    @AppStorage("preferredTerminal")
    private var preferredTerminal = Terminal.terminal.rawValue
    @AppStorage("preferredGitApp")
    private var preferredGitApp = ""
    @State private var terminalLauncher = TerminalLauncher.shared
    @State private var gitAppLauncher = GitAppLauncher.shared
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var errorTitle = "Terminal Launch Failed"

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Terminal selector row
                HStack {
                    Text("Preferred Terminal")
                    Spacer()
                    Button("Test") {
                        Task {
                            do {
                                try terminalLauncher.launchCommand("echo 'VibeTunnel Terminal Test: Success!'")
                            } catch {
                                // Log the error
                                Logger.advanced.error("Failed to launch terminal test: \(error)")

                                // Set up alert content based on error type
                                if let terminalError = error as? TerminalLauncherError {
                                    switch terminalError {
                                    case .appleScriptPermissionDenied:
                                        errorTitle = "Permission Denied"
                                        errorMessage =
                                            "VibeTunnel needs permission to control terminal applications.\n\nPlease grant Automation permission in System Settings > Privacy & Security > Automation."
                                    case .accessibilityPermissionDenied:
                                        errorTitle = "Accessibility Permission Required"
                                        errorMessage =
                                            "VibeTunnel needs Accessibility permission to send keystrokes to \(Terminal(rawValue: preferredTerminal)?.displayName ?? "terminal").\n\nPlease grant permission in System Settings > Privacy & Security > Accessibility."
                                    case .terminalNotFound:
                                        errorTitle = "Terminal Not Found"
                                        errorMessage =
                                            "The selected terminal application could not be found. Please select a different terminal."
                                    case .appleScriptExecutionFailed(let details, let errorCode):
                                        if let code = errorCode {
                                            switch code {
                                            case -1_743:
                                                errorTitle = "Permission Denied"
                                                errorMessage =
                                                    "VibeTunnel needs permission to control terminal applications.\n\nPlease grant Automation permission in System Settings > Privacy & Security > Automation."
                                            case -1_728:
                                                errorTitle = "Terminal Not Available"
                                                errorMessage =
                                                    "The terminal application is not running or cannot be controlled.\n\nDetails: \(details)"
                                            case -1_708:
                                                errorTitle = "Terminal Communication Error"
                                                errorMessage =
                                                    "The terminal did not respond to the command.\n\nDetails: \(details)"
                                            case -25_211:
                                                errorTitle = "Accessibility Permission Required"
                                                errorMessage =
                                                    "System Events requires Accessibility permission to send keystrokes.\n\nPlease grant permission in System Settings > Privacy & Security > Accessibility."
                                            default:
                                                errorTitle = "Terminal Launch Failed"
                                                errorMessage = "AppleScript error \(code): \(details)"
                                            }
                                        } else {
                                            errorTitle = "Terminal Launch Failed"
                                            errorMessage = "Failed to launch terminal: \(details)"
                                        }
                                    case .processLaunchFailed(let details):
                                        errorTitle = "Process Launch Failed"
                                        errorMessage = "Failed to start terminal process: \(details)"
                                    }
                                } else {
                                    errorTitle = "Terminal Launch Failed"
                                    errorMessage = error.localizedDescription
                                }

                                showingError = true
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                    Picker("", selection: $preferredTerminal) {
                        ForEach(Terminal.installed, id: \.rawValue) { terminal in
                            HStack {
                                if let icon = terminal.appIcon {
                                    Image(nsImage: icon.resized(to: NSSize(width: 16, height: 16)))
                                }
                                Text(terminal.displayName)
                            }
                            .tag(terminal.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                // Git app selector row
                HStack {
                    Text("Preferred Git App")
                    Spacer()
                    Picker("", selection: gitAppBinding) {
                        ForEach(GitApp.installed, id: \.rawValue) { gitApp in
                            HStack {
                                if let icon = gitApp.appIcon {
                                    Image(nsImage: icon.resized(to: NSSize(width: 16, height: 16)))
                                }
                                Text(gitApp.displayName)
                            }
                            .tag(gitApp.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        } header: {
            Text("Apps")
                .font(.headline)
        } footer: {
            Text(
                "Configure which applications VibeTunnel uses for terminal sessions and Git repositories."
            )
            .font(.caption)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
        .alert(errorTitle, isPresented: $showingError) {
            Button("OK") {}
            if errorTitle == "Permission Denied" {
                Button("Open System Settings") {
                    if let url =
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } message: {
            Text(errorMessage)
        }
    }

    private var gitAppBinding: Binding<String> {
        Binding(
            get: { 
                // If no preference or invalid preference, use first installed app
                if preferredGitApp.isEmpty || GitApp(rawValue: preferredGitApp) == nil {
                    return GitApp.installed.first?.rawValue ?? ""
                }
                return preferredGitApp
            },
            set: { newValue in
                preferredGitApp = newValue
            }
        )
    }
}

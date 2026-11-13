//
//  MenuBarPopoverView.swift
//  Pupil
//
//  Native macOS-style menu bar tray panel modeled directly after standard
//  system menu bar panels (Docker Desktop / Control Center / Bartender).
//

import SwiftUI

public struct MenuBarPopoverView: View {
    @Bindable var coordinator: SecurityCoordinator
    @Bindable private var settings = PupilSettings.shared

    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    let onClosePopover: () -> Void

    public init(
        coordinator: SecurityCoordinator,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onClosePopover: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.onClosePopover = onClosePopover
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Status Row (e.g. "● Pupil is armed")
            HStack(spacing: 8) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                Text(statusHeadline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text(batteryOrPowerText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            menuDivider

            // Primary Arm / Disarm Action Row
            menuItemButton(
                title: primaryActionTitle,
                systemImage: primaryActionIcon,
                tint: primaryActionColor
            ) {
                handlePrimaryAction()
            }

            menuDivider

            // Quick Toggle Rows
            menuToggleRow(
                title: "Gaze deterrence",
                systemImage: "eye.fill",
                isOn: Binding(
                    get: { settings.gazeDetectionEnabled },
                    set: { val in
                        settings.gazeDetectionEnabled = val
                        if !val {
                            coordinator.setCameraPreviewRequested(false)
                            coordinator.dismissGazeWarning()
                        }
                        coordinator.syncCameraLifecycle()
                    }
                )
            )

            menuToggleRow(
                title: "Blur screen on gaze",
                systemImage: "macwindow.on.rectangle",
                isOn: $settings.blurScreenOnGaze
            )

            menuToggleRow(
                title: "Auto-arm on lock",
                systemImage: "lock.fill",
                isOn: $settings.autoArmOnScreenLock
            )

            menuToggleRow(
                title: "Lock on input",
                systemImage: "keyboard",
                isOn: $settings.lockOnInputWhenArmed
            )

            menuDivider

            // Secondary / Utility Actions
            menuItemButton(
                title: "Settings…",
                systemImage: "gearshape",
                shortcut: "⌘,"
            ) {
                onClosePopover()
                onOpenSettings()
            }

            menuItemButton(
                title: "Simulate Tamper",
                systemImage: "bolt.trianglebadge.exclamationmark"
            ) {
                onClosePopover()
                if coordinator.state == .disarmed {
                    coordinator.startArming(immediate: true)
                }
                coordinator.triggerTamper(source: .manualTest, immediateAlarm: false, simulated: true)
            }

            menuDivider

            // Quit Row
            menuItemButton(
                title: "Quit Pupil",
                systemImage: "power",
                shortcut: "⌘Q"
            ) {
                onClosePopover()
                onQuit()
            }
        }
        .padding(.vertical, 4)
        .frame(width: 250)
    }

    // MARK: - Native Menu Item Rows

    private func menuItemButton(
        title: String,
        systemImage: String,
        shortcut: String? = nil,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(tint == .primary ? Color.secondary : tint)
                    .frame(width: 16, alignment: .center)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(tint)

                Spacer()

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(NativeMenuItemHoverStyle())
    }

    private func menuToggleRow(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.secondary)
                .frame(width: 16, alignment: .center)

            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.primary)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .scaleEffect(0.82)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }

    private var menuDivider: some View {
        Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }

    // MARK: - Status Helpers

    private var statusHeadline: String {
        switch coordinator.state {
        case .disarmed:
            return "Pupil is disarmed"
        case .arming:
            return "Arming (\(coordinator.countdownSecondsRemaining)s)"
        case .armed:
            return "Pupil is armed"
        case .tamperPending:
            return "Tamper alert (\(coordinator.countdownSecondsRemaining)s)"
        case .alarm:
            return "ALARM ACTIVE"
        }
    }

    private var statusDotColor: Color {
        switch coordinator.state {
        case .disarmed:
            return Color.secondary.opacity(0.6)
        case .arming:
            return PupilTheme.warningAmber
        case .armed:
            return PupilTheme.armedGreen
        case .tamperPending:
            return PupilTheme.warningAmber
        case .alarm:
            return PupilTheme.alarmRed
        }
    }

    private var batteryOrPowerText: String {
        coordinator.powerMonitor.isOnACPower ? "Power Adapter" : "Battery"
    }

    private var primaryActionTitle: String {
        switch coordinator.state {
        case .disarmed:
            return "Arm Pupil (\(settings.exitDelaySeconds)s delay)"
        case .arming:
            return "Cancel Arming"
        case .armed, .tamperPending, .alarm:
            return "Disarm Pupil…"
        }
    }

    private var primaryActionIcon: String {
        switch coordinator.state {
        case .disarmed:
            return "lock.shield.fill"
        case .arming:
            return "xmark.circle"
        case .armed, .tamperPending, .alarm:
            return "lock.open.fill"
        }
    }

    private var primaryActionColor: Color {
        switch coordinator.state {
        case .disarmed:
            return PupilTheme.accent
        case .arming:
            return PupilTheme.warningAmber
        case .armed, .tamperPending, .alarm:
            return PupilTheme.alarmRed
        }
    }

    private func handlePrimaryAction() {
        switch coordinator.state {
        case .disarmed:
            coordinator.startArming()
        case .arming:
            coordinator.cancelArmingDuringExitDelay()
        case .armed, .tamperPending, .alarm:
            onClosePopover()
            Task {
                let unlocked = await coordinator.disarmWithTouchID()
                if !unlocked {
                    coordinator.requestInteractiveUnlock()
                }
            }
        }
    }
}

// MARK: - Native Menu Item Hover Effect

private struct NativeMenuItemHoverStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.primary.opacity(0.10) : Color.clear)
            )
            .padding(.horizontal, 4)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

//
//  MenuBarPopoverView.swift
//  Pupil
//
//  Compact macOS tray popover displaying live security status, primary arm/disarm
//  controls, quick feature toggles, and Settings/Quit actions in native UI Kit style.
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
        VStack(alignment: .leading, spacing: 12) {
            // Top Status Header
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pupil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsMetrics.textPrimary)
                    Text(hardwareSummaryText)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                }

                Spacer()

                statusPill
            }

            // Primary Arm / Disarm Action
            Button(action: handlePrimaryAction) {
                HStack(spacing: 6) {
                    Image(systemName: primaryActionIcon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(primaryActionTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(primaryActionColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Quick Controls Group
            SettingsGroup {
                quickToggleRow(
                    title: "Gaze deterrence",
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
                SettingsGroupDivider()
                quickToggleRow(
                    title: "Blur screen on gaze",
                    isOn: $settings.blurScreenOnGaze
                )
                SettingsGroupDivider()
                quickToggleRow(
                    title: "Auto-arm on lock",
                    isOn: $settings.autoArmOnScreenLock
                )
                SettingsGroupDivider()
                quickToggleRow(
                    title: "Lock on input",
                    isOn: $settings.lockOnInputWhenArmed
                )
            }

            // Footer Actions
            HStack(spacing: 8) {
                Button {
                    onClosePopover()
                    onOpenSettings()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 11))
                        Text("Settings…")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(SettingsMetrics.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(SettingsMetrics.rowColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)

                Button {
                    onClosePopover()
                    onQuit()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "power")
                            .font(.system(size: 11))
                        Text("Quit")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(coordinator.isMonitoring ? SettingsMetrics.textTertiary : SettingsMetrics.textSecondary)
                    .frame(width: 72, height: 28)
                    .background(SettingsMetrics.rowColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 284)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func quickToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(SettingsMetrics.textPrimary)
            Spacer()
            PupilToggle(isOn: isOn)
        }
        .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
        .frame(height: 36)
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.14))
        .clipShape(Capsule())
    }

    private var statusText: String {
        switch coordinator.state {
        case .disarmed: return "Disarmed"
        case .arming: return "Arming \(coordinator.countdownSecondsRemaining)s"
        case .armed: return "Armed"
        case .tamperPending: return "Tamper \(coordinator.countdownSecondsRemaining)s"
        case .alarm: return "ALARM"
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .disarmed: return SettingsMetrics.textSecondary
        case .arming: return PupilTheme.warningAmber
        case .armed: return PupilTheme.armedGreen
        case .tamperPending: return PupilTheme.warningAmber
        case .alarm: return PupilTheme.alarmRed
        }
    }

    private var hardwareSummaryText: String {
        let power = coordinator.powerMonitor.isOnACPower ? "AC Power" : "Battery"
        let gaze = settings.gazeDetectionEnabled ? "Gaze On" : "Gaze Off"
        return "\(power) · \(gaze)"
    }

    private var primaryActionTitle: String {
        switch coordinator.state {
        case .disarmed:
            return "Arm Pupil (\(settings.exitDelaySeconds)s)"
        case .arming:
            return "Cancel Arming (\(coordinator.countdownSecondsRemaining)s)"
        case .armed, .tamperPending, .alarm:
            return "Disarm Pupil"
        }
    }

    private var primaryActionIcon: String {
        switch coordinator.state {
        case .disarmed: return "lock.shield.fill"
        case .arming: return "xmark.circle.fill"
        case .armed, .tamperPending, .alarm: return "lock.open.fill"
        }
    }

    private var primaryActionColor: Color {
        switch coordinator.state {
        case .disarmed: return PupilTheme.accent
        case .arming: return PupilTheme.warningAmber
        case .armed: return PupilTheme.armedGreen
        case .tamperPending, .alarm: return PupilTheme.alarmRed
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

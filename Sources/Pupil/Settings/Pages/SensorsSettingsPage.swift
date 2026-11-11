//
//  SensorsSettingsPage.swift
//  Pupil
//
//  Hardware tamper triggers, sleep assertion behavior, and live sensor status.
//

import AppKit
import SwiftUI

public struct SensorsSettingsPage: View {
    @Bindable var coordinator: SecurityCoordinator
    @Bindable private var settings = PupilSettings.shared

    public init(coordinator: SecurityCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsGroup {
                SettingsLabeledOptionRow(
                    title: "Triggers",
                    subtitle: "Choose which physical events trigger the tamper countdown while armed."
                ) {
                    ForEach(HardwareTrigger.allCases) { trigger in
                        let isSelected = settings.hardwareTriggers.contains(trigger)
                        let tint: Color = isSelected
                            ? SettingsMetrics.textPrimary.opacity(0.75)
                            : SettingsMetrics.textSecondary.opacity(0.65)
                        SettingsOptionTile(
                            title: trigger.title,
                            isSelected: isSelected,
                            action: { toggleTrigger(trigger, isSelected: isSelected) },
                            previewHeight: SettingsMetrics.optionPreviewHeight,
                            previewWidth: SettingsMetrics.optionTileWidth
                        ) {
                            Image(systemName: trigger.iconName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(tint)
                        }
                    }
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Prevent sleep during alarm",
                    info: "Keeps your Mac awake while the lid-close alarm is sounding."
                ) {
                    PupilToggle(isOn: $settings.holdSleepOnLidClose)
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Revert on power restored",
                    subtitle: "Cancels countdown and returns to armed if the charger is reconnected before the siren latches."
                ) {
                    PupilToggle(isOn: $settings.revertTamperOnPowerRestored)
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Spatial Motion / Lift Detection",
                    subtitle: "Detects open-lid grab & walk via Apple Vision upper-background registration when unplugged.",
                    info: "Tracks static upper-background ceiling/wall anchors at 10 FPS and ignores brief < 0.5s desk bumps."
                ) {
                    PupilToggle(isOn: Binding(
                        get: { settings.isSpatialMotionEnabled },
                        set: { enabled in
                            settings.isSpatialMotionEnabled = enabled
                            coordinator.syncCameraLifecycle()
                        }
                    ))
                }
                if settings.isSpatialMotionEnabled {
                    SettingsGroupDivider()
                    SettingsOptionSliderRowContent(
                        title: "Motion sensitivity",
                        stepLabels: SpatialMotionSensitivity.allCases.map(\.title),
                        index: $settings.spatialMotionSensitivityIndex,
                        stopCount: SpatialMotionSensitivity.allCases.count
                    )
                    SettingsGroupDivider()
                    liveMotionMeterRow
                    SettingsGroupDivider()
                    spatialFocusInspectionRow
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Hardware Status")
                SettingsGroup {
                    sensorReadoutRow(
                        title: "Power source",
                        icon: coordinator.powerMonitor.isOnACPower ? "bolt.fill" : "battery.75percent",
                        tint: coordinator.powerMonitor.isOnACPower ? PupilTheme.armedGreen : PupilTheme.warningAmber,
                        value: coordinator.powerMonitor.isOnACPower ? "Power Adapter" : "Battery"
                    )
                    SettingsGroupDivider()
                    sensorReadoutRow(
                        title: "Display lid",
                        icon: "laptopcomputer",
                        tint: PupilTheme.armedGreen,
                        value: coordinator.powerMonitor.isLidClosed ? "Closed" : "Open"
                    )
                    SettingsGroupDivider()
                    sensorReadoutRow(
                        title: "Sleep assertion",
                        icon: coordinator.powerMonitor.isSleepAssertionActive ? "bolt.shield.fill" : "moon.zzz",
                        tint: coordinator.powerMonitor.isSleepAssertionActive ? PupilTheme.accent : SettingsMetrics.textSecondary,
                        value: coordinator.powerMonitor.isSleepAssertionActive ? "Active" : "Idle"
                    )
                    SettingsGroupDivider()
                    sensorReadoutRow(
                        title: "Spatial lift sentry",
                        icon: settings.isSpatialMotionEnabled ? "gyroscope" : "xmark.circle",
                        tint: settings.isSpatialMotionEnabled
                            ? (coordinator.state == .armed ? PupilTheme.armedGreen : PupilTheme.accent)
                            : SettingsMetrics.textSecondary,
                        value: settings.isSpatialMotionEnabled
                            ? (coordinator.state == .armed ? "Armed (\(settings.spatialMotionSensitivity.title))" : "Ready (\(settings.spatialMotionSensitivity.title))")
                            : "Off"
                    )
                    SettingsGroupDivider()
                    SettingsRowContent(
                        title: "Room calibration",
                        subtitle: coordinator.activeRoomProfile != nil
                            ? "Jitter \(String(format: "%.3f", coordinator.activeRoomProfile!.noiseFloorScore)) • \(coordinator.activeRoomProfile!.textureHealthDescription)"
                            : "Profiles ambient jitter and texture automatically during arming exit delay."
                    ) {
                        HStack(spacing: 8) {
                            if coordinator.isLiveCalibrating {
                                HStack(spacing: 5) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("\(coordinator.liveCalibrationSecondsRemaining)s")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(PupilTheme.accent)
                                }
                            } else if let profile = coordinator.activeRoomProfile {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(PupilTheme.armedGreen)
                                        .font(.system(size: 12))
                                    Text(profile.noiseLevelDescription)
                                        .font(.system(size: 12))
                                        .foregroundStyle(SettingsMetrics.textSecondary)
                                }
                            } else {
                                Text("Uncalibrated")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SettingsMetrics.textTertiary)
                            }

                            PillActionButton(
                                title: coordinator.isLiveCalibrating ? "Stop" : "Test"
                            ) {
                                if coordinator.isLiveCalibrating {
                                    coordinator.cancelLiveCalibrationTest()
                                } else {
                                    coordinator.startLiveCalibrationTest(durationSeconds: 3.0)
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Phone Companion")
                SettingsGroup {
                    SettingsRowContent(
                        title: "Lock-screen phone alerts",
                        subtitle: "Pushes encrypted alerts straight to your locked iPhone via Apple Web Push (APNs) on tamper or siren events.",
                        info: "One-time QR pairing using W3C Web Push (RFC 8291 + VAPID). Works across Wi-Fi and cellular with zero re-pairing."
                    ) {
                        PupilToggle(isOn: $settings.relayEnabled)
                    }

                    SettingsGroupDivider()

                    if let sub = coordinator.webPushManager.activeSubscription {
                        SettingsRowContent(
                            title: "Paired device",
                            subtitle: "\(sub.deviceName) • \(sub.endpointHost)"
                        ) {
                            HStack(spacing: 8) {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(PupilTheme.armedGreen)
                                        .frame(width: 7, height: 7)
                                    Text("Paired")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(PupilTheme.armedGreen)
                                }

                                Button("Send Test Alert") {
                                    Task {
                                        if !settings.relayEnabled {
                                            settings.relayEnabled = true
                                        }
                                        _ = await coordinator.webPushManager.sendPushNotification(
                                            title: "Pupil Test Alert",
                                            body: "Your locked phone is receiving direct security alerts from your MacBook.",
                                            severity: "high",
                                            tag: "pupil-test"
                                        )
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(coordinator.webPushManager.isSendingPush)

                                Button("Unpair") {
                                    coordinator.webPushManager.unpairPhone()
                                    coordinator.webPushManager.startPairingListener()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    } else {
                        HStack(alignment: .center, spacing: 16) {
                            if let qrImage = coordinator.webPushManager.makePairingQRCodeImage(dimension: 120) {
                                Image(nsImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .frame(width: 120, height: 120)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.white)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text("One-Time iPhone Pairing")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(SettingsMetrics.textPrimary)
                                    if coordinator.webPushManager.isListeningForPairing {
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                }

                                Text("1. Scan QR code once with your iPhone Camera.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(SettingsMetrics.textSecondary)
                                Text("2. Tap Share → Add to Home Screen, then open Pupil.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(SettingsMetrics.textSecondary)
                                Text("3. Tap 'Pair & Enable Lock-Screen Alerts' — pairs automatically.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(SettingsMetrics.textSecondary)

                                HStack(spacing: 8) {
                                    Button("Paste Pairing Code") {
                                        coordinator.webPushManager.pastePairingFromClipboard()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Fallback if automatic pairing is blocked by network firewall (uses Apple Universal Clipboard).")

                                    Button("Copy Link") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(coordinator.webPushManager.pairingURLString, forType: .string)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.top, 4)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
                        .padding(.vertical, 12)
                    }

                    if let status = coordinator.webPushManager.statusMessage, !status.isEmpty {
                        SettingsGroupDivider()
                        HStack(spacing: 6) {
                            Image(systemName: coordinator.webPushManager.lastPushSucceeded ? "checkmark.circle.fill" : "info.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(coordinator.webPushManager.lastPushSucceeded ? PupilTheme.armedGreen : PupilTheme.warningAmber)
                            Text(status)
                                .font(.system(size: 11.5))
                                .foregroundStyle(SettingsMetrics.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .onAppear {
            if settings.isSpatialMotionEnabled && coordinator.state == .disarmed {
                coordinator.setCameraPreviewRequested(true)
            }
            if !coordinator.webPushManager.isPaired {
                coordinator.webPushManager.startPairingListener()
            }
        }
        .onDisappear {
            if coordinator.state == .disarmed {
                coordinator.setCameraPreviewRequested(false)
            }
            coordinator.webPushManager.stopPairingListener()
        }
    }

    private var liveMotionMeterRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Live displacement")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsMetrics.textPrimary)
                Spacer()
                Text(String(format: "%.0f%%", min(100, coordinator.latestMotionDisplacementScore * 100)))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(motionMeterColor(coordinator.latestMotionDisplacementScore))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 6)

                    Capsule()
                        .fill(motionMeterColor(coordinator.latestMotionDisplacementScore))
                        .frame(
                            width: max(4, geo.size.width * CGFloat(min(1.0, coordinator.latestMotionDisplacementScore))),
                            height: 6
                        )
                        .animation(.linear(duration: 0.1), value: coordinator.latestMotionDisplacementScore)
                }
            }
            .frame(height: 6)

            HStack {
                Text("Resting (0%)")
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsMetrics.textTertiary)
                Spacer()
                Text("Tamper threshold (100%)")
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsMetrics.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func motionMeterColor(_ score: Float) -> Color {
        if score < 0.40 {
            return PupilTheme.armedGreen
        } else if score < 0.85 {
            return PupilTheme.warningAmber
        } else {
            return PupilTheme.alarmRed
        }
    }

    private func toggleTrigger(_ trigger: HardwareTrigger, isSelected: Bool) {
        if isSelected {
            guard settings.hardwareTriggers.count > 1 else { return }
            settings.hardwareTriggers.remove(trigger)
        } else {
            settings.hardwareTriggers.insert(trigger)
        }
    }

    private func sensorReadoutRow(title: String, icon: String, tint: Color, value: String) -> some View {
        SettingsRowContent(title: title) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsMetrics.textSecondary)
            }
        }
    }

    private var spatialFocusInspectionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus & calibration inspection")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SettingsMetrics.textPrimary)
                    Text("Verify active room background tracking and foreground face exclusion.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                }
                Spacer()
                PillActionButton(
                    title: coordinator.isCameraPreviewRequested ? "Hide inspection" : "Inspect focus"
                ) {
                    toggleSpatialInspection()
                }
            }

            if coordinator.isCameraPreviewRequested {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottomTrailing) {
                        CameraPreviewView(session: coordinator.cameraManager.captureSessionReference)
                        SpatialFocusOverlayView(coordinator: coordinator)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: SettingsMetrics.rowRadius,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: SettingsMetrics.rowRadius
                        )
                    )

                    Rectangle()
                        .fill(SettingsMetrics.rowBorder)
                        .frame(height: SettingsMetrics.rowBorderWidth)

                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(coordinator.isTextureAdequate ? PupilTheme.armedGreen : PupilTheme.warningAmber)
                                .frame(width: 6, height: 6)
                            Text(coordinator.isTextureAdequate ? "Background texture reliable" : "Low texture (< 0.006)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(SettingsMetrics.textSecondary)
                        }

                        Spacer()

                        PillActionButton(
                            title: coordinator.isLiveCalibrating
                                ? "Sampling (\(coordinator.liveCalibrationSecondsRemaining)s)..."
                                : "Test Calibration (3s)"
                        ) {
                            if coordinator.isLiveCalibrating {
                                coordinator.cancelLiveCalibrationTest()
                            } else {
                                coordinator.startLiveCalibrationTest(durationSeconds: 3.0)
                            }
                        }
                    }
                    .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
                    .frame(height: SettingsMetrics.rowHeight)
                }
                .background(SettingsMetrics.rowColor)
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius)
                        .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius))
                .transition(.opacity)

                if let report = coordinator.liveCalibrationReport {
                    calibrationReportSummary(report)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func toggleSpatialInspection() {
        if coordinator.isCameraPreviewRequested {
            withAnimation(.easeInOut(duration: 0.18)) {
                coordinator.setCameraPreviewRequested(false)
            }
        } else {
            Task {
                let granted = await coordinator.cameraManager.requestCameraAccess()
                if granted {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        coordinator.setCameraPreviewRequested(true)
                    }
                }
            }
        }
    }

    private func calibrationReportSummary(_ report: RoomCalibrationProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(PupilTheme.armedGreen)
                    Text("Calibration Profile: \(report.noiseLevelDescription)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SettingsMetrics.textPrimary)
                }
                Spacer()
                Text("Noise \(String(format: "%.3f", report.noiseFloorScore))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PupilTheme.armedGreen)
            }

            HStack(spacing: 12) {
                Text("Texture: \(String(format: "%.3f", report.averageTextureEnergy)) (\(report.textureHealthDescription))")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsMetrics.textSecondary)
                Spacer()
                Text("Rec: \(report.recommendedSensitivity.title)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PupilTheme.accent)
            }
        }
        .padding(10)
        .background(SettingsMetrics.rowColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(PupilTheme.armedGreen.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

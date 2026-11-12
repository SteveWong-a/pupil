//
//  GazeSettingsPage.swift
//  Pupil
//
//  Camera & Gaze settings page modeled directly after Glance's CameraSettingsPage
//  and RecognitionSettingsPage, featuring a real on-demand AVCaptureVideoPreviewLayer.
//

import AVFoundation
import SwiftUI

public struct GazeSettingsPage: View {
    @Bindable var coordinator: SecurityCoordinator
    @Bindable private var settings = PupilSettings.shared

    public init(coordinator: SecurityCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsGroup {
                SettingsRowContent(title: "Gaze deterrence") {
                    PupilToggle(isOn: Binding(
                        get: { settings.gazeDetectionEnabled },
                        set: { val in
                            settings.gazeDetectionEnabled = val
                            if !val {
                                coordinator.setCameraPreviewRequested(false)
                                coordinator.dismissGazeWarning()
                            }
                            coordinator.syncCameraLifecycle()
                        }
                    ))
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Blur screen on gaze",
                    info: "Instantly covers display content with frosted glass while someone looks at your screen, clearing when they look away."
                ) {
                    PupilToggle(isOn: $settings.blurScreenOnGaze)
                }
                SettingsGroupDivider()
                cameraDevicePickerRow
                SettingsGroupDivider()
                SettingsLabeledOptionRow(
                    title: "Style",
                    subtitle: "Choose how Pupil responds when someone looks at your screen."
                ) {
                    ForEach(NotchDeterrentStyle.allCases) { style in
                        let isSelected = settings.notchStyle == style
                        SettingsOptionTile(
                            title: style.title,
                            isSelected: isSelected,
                            action: {
                                settings.notchStyle = style
                                coordinator.simulateGazeWarning()
                            },
                            previewHeight: SettingsMetrics.optionPreviewHeight,
                            previewWidth: SettingsMetrics.optionTileWidth
                        ) {
                            deterrentStylePreview(style, isSelected: isSelected)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Sensitivity")
                SettingsGroup {
                    SettingsOptionSliderRowContent(
                        title: "Detection cone",
                        stepLabels: GazeSensitivity.allCases.map(\.title),
                        index: $settings.gazeSensitivityIndex,
                        stopCount: GazeSensitivity.allCases.count
                    )
                    SettingsGroupDivider()
                    SettingsSteppedSliderRowContent(
                        title: "Dwell duration",
                        valueLabel: String(format: "%.1f seconds", settings.dwellThresholdSeconds),
                        index: $settings.dwellSliderIndex,
                        stopCount: PupilSettings.dwellStops.count
                    )
                }
                SettingsCaption(text: "Higher sensitivity detects wider peripheral angles (Ultra catches side shoulder-surfing); dwell duration controls how quickly the privacy blur or deterrent triggers.")
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Preview")
                liveCameraPreviewCard

                SettingsGroup {
                    if settings.isSpatialMotionEnabled {
                        liveDisplacementRow
                        SettingsGroupDivider()
                        spatialRoomFocusRow
                        SettingsGroupDivider()
                    }
                    gazeDwellRow
                }

                if settings.isSpatialMotionEnabled, let report = coordinator.liveCalibrationReport {
                    calibrationReportCard(report)
                }
                SettingsCaption(
                    text: settings.isSpatialMotionEnabled
                        ? "Live displacement, spatial focus, and gaze dwell activate when preview is running. All frames are processed in memory and never saved."
                        : "Gaze dwell tracking activates when preview is running. All frames are processed in memory and never saved."
                )
            }
        }
        .onDisappear {
            coordinator.setCameraPreviewRequested(false)
        }
    }

    private var cameraDevicePickerRow: some View {
        SettingsRowContent(title: "Camera") {
            SettingsMenuPickerPill(label: selectedCameraName) {
                Button("Default (\(defaultCameraName))") {
                    settings.preferredCameraID = nil
                }
                if !coordinator.cameraManager.availableCameras.isEmpty {
                    Divider()
                    ForEach(coordinator.cameraManager.availableCameras) { cam in
                        Button(cam.name) {
                            settings.preferredCameraID = cam.id
                        }
                    }
                }
            }
        }
    }

    private var defaultCameraName: String {
        coordinator.cameraManager.availableCameras.first?.name ?? "Built-in Camera"
    }

    private var selectedCameraName: String {
        guard let id = settings.preferredCameraID,
              let match = coordinator.cameraManager.availableCameras.first(where: { $0.id == id }) else {
            return "Default (\(defaultCameraName))"
        }
        return match.name
    }

    @ViewBuilder
    private func deterrentStylePreview(_ style: NotchDeterrentStyle, isSelected: Bool) -> some View {
        let tint: Color = isSelected
            ? SettingsMetrics.textPrimary.opacity(0.75)
            : SettingsMetrics.textSecondary.opacity(0.65)
        switch style {
        case .minimalPill:
            Capsule()
                .fill(tint)
                .frame(width: 50, height: 14)
        case .silent:
            Image(systemName: "eye.slash")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
        }
    }

    private var dwellPercentage: Int {
        Int((min(1.0, max(0.0, coordinator.gazeDwellProgress)) * 100).rounded())
    }

    private var isCameraActive: Bool {
        coordinator.isCameraPreviewRequested && coordinator.cameraManager.isRunning
    }

    private var liveCameraPreviewCard: some View {
        VStack(spacing: 0) {
            ZStack {
                if coordinator.isCameraPreviewRequested {
                    CameraPreviewView(session: coordinator.cameraManager.captureSessionReference)
                        .transition(.opacity)
                    if settings.isSpatialMotionEnabled {
                        SpatialFocusOverlayView(coordinator: coordinator)
                            .transition(.opacity)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(SettingsMetrics.textTertiary)
                        Text("Preview is off")
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsMetrics.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 196)
            .background(Color(white: 0, opacity: 0.18))
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
                HStack(spacing: 8) {
                    Circle()
                        .fill(isCameraActive ? (coordinator.activeFaceCount > 0 ? PupilTheme.accent : SettingsMetrics.textSecondary) : SettingsMetrics.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(cameraStatusText)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                }

                Spacer()

                if settings.isSpatialMotionEnabled && coordinator.isCameraPreviewRequested {
                    PillActionButton(
                        title: coordinator.isLiveCalibrating ? "Stop Test" : "Test Calibration"
                    ) {
                        if coordinator.isLiveCalibrating {
                            coordinator.cancelLiveCalibrationTest()
                        } else {
                            coordinator.startLiveCalibrationTest(durationSeconds: 3.0)
                        }
                    }
                }
                PillActionButton(
                    title: coordinator.isCameraPreviewRequested ? "Hide preview" : "Show preview"
                ) {
                    togglePreview()
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
    }

    private var cameraStatusText: String {
        guard isCameraActive else { return "Preview is off" }
        if coordinator.activeFaceCount > 0 {
            return "Subject detected"
        }
        return settings.isSpatialMotionEnabled ? "Room background ready" : "Monitoring active"
    }

    // MARK: - Native Percentage Bar Rows (Matching macOS UI)

    private var isDisplacementReady: Bool {
        isCameraActive && coordinator.hasMotionAnchor
    }

    private var liveDisplacementRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Live displacement")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsMetrics.textPrimary)
                Spacer()
                if isDisplacementReady {
                    Button {
                        coordinator.resetSurroundingsBaseline()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("Reset")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SettingsMetrics.textSecondary)
                    .help("Re-zeros anchor against current room surroundings")

                    Text(String(format: "%.0f%%", min(100, coordinator.latestMotionDisplacementScore * 100)))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(motionMeterColor(coordinator.latestMotionDisplacementScore))
                } else {
                    Text("N/A")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettingsMetrics.textTertiary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 6)

                    if isDisplacementReady {
                        Capsule()
                            .fill(coordinator.latestMotionDisplacementScore >= 0.85 ? PupilTheme.alarmRed : (coordinator.latestMotionDisplacementScore >= 0.40 ? PupilTheme.warningAmber : PupilTheme.accent))
                            .frame(
                                width: max(4, geo.size.width * CGFloat(min(1.0, coordinator.latestMotionDisplacementScore))),
                                height: 6
                            )
                            .animation(.linear(duration: 0.1), value: coordinator.latestMotionDisplacementScore)
                    }
                }
            }
            .frame(height: 6)

            HStack {
                Text(!isCameraActive ? "Camera offline" : (!coordinator.hasMotionAnchor ? "Acquiring anchor..." : "Resting (0%)"))
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

    private var spatialRoomFocusPercentage: Int {
        guard isCameraActive else { return 0 }
        if coordinator.latestFaceBoundingBoxes.isEmpty {
            return 100
        }
        let maskedArea = coordinator.latestFaceBoundingBoxes.reduce(0.0) { sum, box in
            sum + Double(box.width * 1.25 * box.height * 1.25)
        }
        return max(40, min(100, Int(((1.0 - min(0.60, maskedArea)) * 100).rounded())))
    }

    private var spatialRoomFocusRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Spatial room focus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsMetrics.textPrimary)
                Spacer()
                if isCameraActive {
                    Text("\(spatialRoomFocusPercentage)%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettingsMetrics.textPrimary)
                } else {
                    Text("N/A")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettingsMetrics.textTertiary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 6)

                    if isCameraActive {
                        Capsule()
                            .fill(PupilTheme.accent)
                            .frame(
                                width: max(4, geo.size.width * CGFloat(spatialRoomFocusPercentage) / 100.0),
                                height: 6
                            )
                            .animation(.linear(duration: 0.1), value: spatialRoomFocusPercentage)
                    }
                }
            }
            .frame(height: 6)

            HStack {
                Text(isCameraActive ? (coordinator.latestFaceBoundingBoxes.isEmpty ? "Full room background" : "\(coordinator.latestFaceBoundingBoxes.count) subject masked") : "Tracking inactive")
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsMetrics.textTertiary)
                Spacer()
                Text(isCameraActive ? (coordinator.isTextureAdequate ? "Texture adequate (\(String(format: "%.3f", coordinator.latestTextureEnergy)))" : "Low texture (< 0.006)") : "No texture data")
                    .font(.system(size: 10))
                    .foregroundStyle(isCameraActive && !coordinator.isTextureAdequate ? PupilTheme.warningAmber : SettingsMetrics.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var gazeDwellRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Gaze dwell progress")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsMetrics.textPrimary)
                Spacer()
                if isCameraActive {
                    Text("\(dwellPercentage)%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(dwellPercentage >= 100 ? PupilTheme.warningAmber : SettingsMetrics.textPrimary)
                } else {
                    Text("N/A")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettingsMetrics.textTertiary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 6)

                    if isCameraActive {
                        Capsule()
                            .fill(dwellPercentage >= 100 ? PupilTheme.warningAmber : PupilTheme.accent)
                            .frame(
                                width: max(4, geo.size.width * CGFloat(min(1.0, coordinator.gazeDwellProgress))),
                                height: 6
                            )
                            .animation(.easeOut(duration: 0.12), value: coordinator.gazeDwellProgress)
                    }
                }
            }
            .frame(height: 6)

            HStack {
                Text(isCameraActive ? "0s (Resting)" : "Inference idle")
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsMetrics.textTertiary)
                Spacer()
                Text("\(String(format: "%.1fs", settings.dwellThresholdSeconds)) (Trigger threshold)")
                    .font(.system(size: 10))
                    .foregroundStyle(SettingsMetrics.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func motionMeterColor(_ score: Float) -> Color {
        if score < 0.40 {
            return SettingsMetrics.textPrimary
        } else if score < 0.85 {
            return PupilTheme.warningAmber
        } else {
            return PupilTheme.alarmRed
        }
    }

    private func togglePreview() {
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

    private func calibrationReportCard(_ report: RoomCalibrationProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                    Text("Room Noise & Focus Profile")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SettingsMetrics.textPrimary)
                }
                Spacer()
                Text("Active Baseline")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SettingsMetrics.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    reportCell(
                        label: "Noise Floor",
                        value: String(format: "%.3f", report.noiseFloorScore),
                        detail: report.noiseLevelDescription
                    )
                    reportCell(
                        label: "Texture Energy",
                        value: String(format: "%.3f", report.averageTextureEnergy),
                        detail: report.textureHealthDescription
                    )
                }
                GridRow {
                    reportCell(
                        label: "Ambient Light",
                        value: String(format: "%.0f%%", report.averageLuminance * 100),
                        detail: report.luminanceDescription
                    )
                    reportCell(
                        label: "Recommended Sentry",
                        value: report.recommendedSensitivity.title,
                        detail: "Optimal for noise floor"
                    )
                }
            }
        }
        .padding(12)
        .background(SettingsMetrics.rowColor)
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius)
                .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func reportCell(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettingsMetrics.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettingsMetrics.textPrimary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(SettingsMetrics.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

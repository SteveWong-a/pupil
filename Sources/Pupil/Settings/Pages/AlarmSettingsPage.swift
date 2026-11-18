//
//  AlarmSettingsPage.swift
//  Pupil
//
//  Siren tone configuration, test actions, and session activity log.
//

import SwiftUI

public struct AlarmSettingsPage: View {
    @Bindable var coordinator: SecurityCoordinator
    @Bindable private var settings = PupilSettings.shared

    private static let frequencyPresets: [Int] = [660, 880, 1046, 1320]

    public init(coordinator: SecurityCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsGroup {
                SettingsRowContent(title: "Siren tone") {
                    SettingsMenuPickerPill(label: "\(settings.sirenFrequencyHz) Hz") {
                        ForEach(Self.frequencyPresets, id: \.self) { freq in
                            Button("\(freq) Hz") {
                                settings.sirenFrequencyHz = freq
                            }
                        }
                    }
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Force built-in speakers & unmute",
                    subtitle: "Routes the theft alarm to MacBook speakers and unmutes audio even if headphones are plugged in."
                ) {
                    PupilToggle(isOn: $settings.sirenSpeakerOverrideEnabled)
                }
                SettingsGroupDivider()
                locationEnvironmentRow
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Progressive siren escalation",
                    subtitle: "Starts the alarm at 30% and builds to your configured volume instead of blasting immediately."
                ) {
                    PupilToggle(isOn: $settings.sirenEscalationCurveEnabled)
                }
                if settings.sirenEscalationCurveEnabled {
                    SettingsGroupDivider()
                    SettingsRowContent(
                        title: "Escalation curve",
                        subtitle: settings.sirenEscalationProfile.subtitle
                    ) {
                        SettingsMenuPickerPill(label: settings.sirenEscalationProfile.title) {
                            ForEach(SirenEscalationProfile.allCases) { profile in
                                Button(profile.title) {
                                    settings.sirenEscalationProfile = profile
                                }
                            }
                        }
                    }
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "Test speaker") {
                    PillActionButton(title: "Play sound") {
                        SirenSynthesizer.shared.playTestChirp(baseFrequencyHz: Double(settings.sirenFrequencyHz))
                    }
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Countdown warning ticks",
                    subtitle: "Plays a subtle acoustic click every second during the grace period."
                ) {
                    PupilToggle(isOn: $settings.countdownChimeEnabled)
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Simulate tamper",
                    subtitle: "Starts a test countdown in the notch."
                ) {
                    HoldToConfirmButton(title: "Hold to test", holdDuration: 1.0) {
                        if coordinator.state == .disarmed {
                            coordinator.startArming(immediate: true)
                        }
                        coordinator.triggerTamper(source: .manualTest, immediateAlarm: false, simulated: true)
                    }
                }
            }
            .animation(SettingsMetrics.stateTransitionAnimation, value: settings.sirenEscalationCurveEnabled)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SettingsSectionTitle(text: "Activity")
                    Spacer()
                    if !coordinator.events.isEmpty {
                        HStack(spacing: 8) {
                            PillActionButton(title: "Export log") {
                                coordinator.presentExportIncidentLogPanel()
                            }
                            Button("Clear") {
                                coordinator.clearEventLog()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PupilTheme.accent)
                        }
                        .padding(.trailing, 8)
                        .padding(.top, SettingsMetrics.sectionTitleVerticalPadding)
                    }
                }

                SettingsGroup {
                    if coordinator.events.isEmpty {
                        HStack {
                            Spacer()
                            Text("No recent activity")
                                .font(.system(size: 13))
                                .foregroundStyle(SettingsMetrics.textTertiary)
                                .padding(.vertical, 22)
                            Spacer()
                        }
                    } else {
                        ForEach(Array(coordinator.events.prefix(10).enumerated()), id: \.element.id) { index, event in
                            if index > 0 {
                                SettingsGroupDivider()
                            }
                            HStack(alignment: .center, spacing: 10) {
                                Circle()
                                    .fill(dotColor(for: event.stateAtEvent))
                                    .frame(width: 6, height: 6)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(SettingsMetrics.textPrimary)
                                    Text(event.detail)
                                        .font(.system(size: 11))
                                        .foregroundStyle(SettingsMetrics.textTertiary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(SettingsMetrics.textSecondary)
                                    Text(relativeTimeString(for: event.timestamp))
                                        .font(.system(size: 10))
                                        .foregroundStyle(SettingsMetrics.textTertiary)
                                }
                            }
                            .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    private var locationEnvironmentValueLabel: String {
        let pct = Int((settings.sirenOverrideVolume * 100).rounded())
        let preset = settings.activeEnvironmentPreset
        if preset == .custom {
            return "Custom · \(pct)%"
        }
        return "\(preset.title) · \(pct)%"
    }

    private var locationEnvironmentRow: some View {
        SettingsEnvironmentSliderRowContent(
            title: "Location environment",
            valueLabel: locationEnvironmentValueLabel,
            value: $settings.sirenOverrideVolume,
            presets: EnvironmentPreset.fixedPresets.compactMap { preset in
                guard let volume = preset.volume else { return nil }
                return (label: preset.title, targetValue: volume)
            },
            isEnabled: settings.sirenSpeakerOverrideEnabled
        )
    }

    private func relativeTimeString(for date: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))
        if elapsed < 5 { return "just now" }
        if elapsed < 60 { return "\(elapsed)s ago" }
        let mins = elapsed / 60
        if mins < 60 { return "\(mins)m ago" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }

    private func dotColor(for state: SecurityState) -> Color {
        switch state {
        case .disarmed: return .secondary
        case .arming: return PupilTheme.warningAmber
        case .armed: return PupilTheme.armedGreen
        case .tamperPending: return PupilTheme.warningAmber
        case .alarm: return PupilTheme.alarmRed
        }
    }
}

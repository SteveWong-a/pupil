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
                    title: "Force Built-in Speakers & Unmute",
                    subtitle: "Routes the theft alarm to MacBook speakers and unmutes audio even if headphones are plugged in."
                ) {
                    PupilToggle(isOn: $settings.sirenSpeakerOverrideEnabled)
                }
                SettingsGroupDivider()
                locationEnvironmentRow
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

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SettingsSectionTitle(text: "Activity")
                    Spacer()
                    if !coordinator.events.isEmpty {
                        Button("Clear") {
                            coordinator.clearEventLog()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PupilTheme.accent)
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

    private var locationEnvironmentBadgeText: String {
        let preset = settings.activeEnvironmentPreset
        if preset == .custom {
            return "Custom (\(Int((settings.sirenOverrideVolume * 100).rounded()))%)"
        }
        return preset.title
    }

    private var locationEnvironmentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location Environment")
                        .font(SettingsMetrics.rowFont)
                        .foregroundStyle(SettingsMetrics.textPrimary)
                    Text("Sets siren speaker volume when an alarm latches.")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsMetrics.textTertiary)
                }

                Spacer()

                Text(locationEnvironmentBadgeText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settings.activeEnvironmentPreset == .custom ? PupilTheme.warningAmber : PupilTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(
                                (settings.activeEnvironmentPreset == .custom ? PupilTheme.warningAmber : PupilTheme.accent)
                                    .opacity(0.14)
                            )
                    )
            }

            Slider(value: $settings.sirenOverrideVolume, in: 0.10...1.00)
                .tint(PupilTheme.accent)
                .disabled(!settings.sirenSpeakerOverrideEnabled)

            HStack(spacing: 8) {
                ForEach(EnvironmentPreset.fixedPresets) { preset in
                    let isSelected = settings.activeEnvironmentPreset == preset
                    Button {
                        if let presetVolume = preset.volume {
                            settings.sirenOverrideVolume = presetVolume
                        }
                    } label: {
                        Text("\(preset.title) (\(Int(((preset.volume ?? 0.80) * 100).rounded()))%)")
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? PupilTheme.accent : SettingsMetrics.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? PupilTheme.accent.opacity(0.14) : SettingsMetrics.pickerPillFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!settings.sirenSpeakerOverrideEnabled)

                    if preset != EnvironmentPreset.fixedPresets.last {
                        Spacer(minLength: 4)
                    }
                }
            }
        }
        .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
        .padding(.vertical, SettingsMetrics.sliderRowVerticalPadding)
        .opacity(settings.sirenSpeakerOverrideEnabled ? 1.0 : 0.55)
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

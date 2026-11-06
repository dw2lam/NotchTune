import AppKit
import NotchTuneCore
import SwiftUI

/// Setup's answer to "is NotchTune hearing from my agents?": one row per set
/// up agent with what's wrong in plain words, and a test that doesn't need the
/// agent running. Agents that aren't set up share one quiet line.
struct IntegrationDoctorCard: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }
    private var hooks: HookInstallationCoordinator { model.hooks }

    private var activeReports: [IntegrationDiagnosis] {
        hooks.doctorReports.filter { $0.status != .notInstalled }
    }

    private var notInstalledNames: [String] {
        hooks.doctorReports.filter { $0.status == .notInstalled }.map(\.displayName)
    }

    private var needingAttention: Int {
        activeReports.filter { $0.status == .needsRepair }.count
    }

    /// Re-examines when an install lands, not on a timer.
    private var installedAgents: [AgentIdentifier] {
        AgentIdentifier.hookAgents.filter(hooks.isHookInstalled)
    }

    var body: some View {
        SettingsCard(
            title: lang.t("setup.section.diagnostics"),
            footer: lang.t("doctor.restartHint")
        ) {
            Button(lang.t("setup.diagnostics.recheck")) {
                model.runHealthChecks()
            }
        } content: {
            summaryRow

            ForEach(activeReports) { report in
                SettingsRowDivider()
                DoctorAgentRow(model: model, report: report)
            }

            if !notInstalledNames.isEmpty {
                SettingsRowDivider()
                SettingsRow {
                    Text(lang.t("doctor.notInstalled", notInstalledNames.joined(separator: ", ")))
                        .font(SettingsMetrics.rowSubtitleFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } accessory: {
                    EmptyView()
                }
            }
        }
        .task(id: installedAgents) {
            model.runHealthChecks()
        }
    }

    private var summaryRow: some View {
        SettingsRow {
            HStack(spacing: 10) {
                Image(systemName: summarySymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(summaryColor)
                Text(summaryText)
                    .font(SettingsMetrics.rowTitleFont)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } accessory: {
            EmptyView()
        }
    }

    private var summaryText: String {
        if hooks.doctorReports.isEmpty {
            return lang.t("setup.diagnostics.notRun")
        }
        if activeReports.isEmpty {
            return lang.t("doctor.summary.noneSetUp")
        }
        if needingAttention > 0 {
            return lang.t("setup.diagnostics.issuesFound")
        }
        return lang.t("setup.diagnostics.allHealthy")
    }

    private var summarySymbol: String {
        if needingAttention > 0 {
            return "exclamationmark.triangle.fill"
        }
        return activeReports.isEmpty ? "stethoscope" : "checkmark.circle.fill"
    }

    private var summaryColor: Color {
        if needingAttention > 0 {
            return SettingsTheme.caution
        }
        return activeReports.isEmpty ? .secondary : SettingsTheme.positive
    }
}

private struct DoctorAgentRow: View {
    var model: AppModel
    let report: IntegrationDiagnosis

    private var lang: LanguageManager { model.lang }
    private var hooks: HookInstallationCoordinator { model.hooks }

    var body: some View {
        SettingsRow(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(report.displayName)
                        .font(SettingsMetrics.rowTitleFont)
                    Text(statusLine)
                        .font(SettingsMetrics.rowSubtitleFont)
                        .foregroundStyle(.secondary)
                }

                ForEach(explanations, id: \.self) { line in
                    detail(line, color: .primary)
                }

                if report.droppedEvents > 0 {
                    detail(droppedLine, color: .secondary)
                }

                if let result = hooks.hookTestResults[report.agent] {
                    detail(
                        DoctorCopy.testResult(result, lang: lang),
                        color: result.didPass ? SettingsTheme.positive : SettingsTheme.critical
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } accessory: {
            HStack(spacing: 8) {
                fixButton

                if hooks.hookTestsRunning.contains(report.agent) {
                    ProgressView().controlSize(.small)
                } else {
                    Button(lang.t("doctor.test")) {
                        hooks.testHook(for: report.agent)
                    }
                    .help(lang.t("doctor.test.help"))
                }
            }
        }
    }

    private func detail(_ text: String, color: Color) -> some View {
        Text(text)
            .font(SettingsMetrics.rowSubtitleFont)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 14)
    }

    @ViewBuilder
    private var fixButton: some View {
        switch report.fix {
        case .reinstall:
            Button(lang.t("setup.diagnostics.repair")) {
                hooks.installHooks(for: report.agent)
            }
        case let .openConfig(url):
            Button(lang.t("doctor.showConfig")) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case nil:
            EmptyView()
        }
    }

    private var explanations: [String] {
        report.findings.map { DoctorCopy.explanation($0, lang: lang) }
    }

    private var droppedLine: String {
        if let event = report.lastDroppedEvent {
            return lang.t("doctor.dropped.named", report.droppedEvents, event)
        }
        return lang.t("doctor.dropped", report.droppedEvents)
    }

    private var statusColor: Color {
        switch report.status {
        case .working: SettingsTheme.positive
        case .noEventsYet: SettingsTheme.informative
        case .needsRepair: SettingsTheme.caution
        case .notInstalled: SettingsTheme.paper.opacity(0.3)
        }
    }

    private var statusLine: String {
        let status: String
        switch report.status {
        case .working: status = lang.t("doctor.status.working")
        case .noEventsYet: status = lang.t("doctor.status.noEvents")
        case .needsRepair: status = lang.t("doctor.status.needsRepair")
        case .notInstalled: status = lang.t("setup.hookMissing")
        }

        guard let lastEventAt = report.lastEventAt else {
            return status
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let when = formatter.localizedString(for: lastEventAt, relativeTo: .now)
        return "\(status) · \(lang.t("doctor.lastEvent", when))"
    }
}

/// Plain sentences for the doctor's findings. Core reports what's wrong; this
/// is where it becomes something a person can act on.
enum DoctorCopy {
    static func explanation(_ finding: IntegrationDiagnosis.Finding, lang: LanguageManager) -> String {
        switch finding {
        case .hooksMissing: lang.t("doctor.finding.hooksMissing")
        case .configMalformed: lang.t("doctor.finding.configMalformed")
        case .configUnreadable: lang.t("doctor.finding.configUnreadable")
        case .binaryMissing: lang.t("doctor.finding.binaryMissing")
        case .binaryNotExecutable: lang.t("doctor.finding.binaryNotExecutable")
        case .staleCommand: lang.t("doctor.finding.staleCommand")
        case .pluginMissing: lang.t("doctor.finding.pluginMissing")
        case .pluginOutdated: lang.t("doctor.finding.pluginOutdated")
        case .claudeHooksDisabled: lang.t("doctor.finding.claudeHooksDisabled")
        case .claudeManagedHooksOnly: lang.t("doctor.finding.claudeManagedHooksOnly")
        case .codexHooksOff: lang.t("doctor.finding.codexHooksOff")
        case let .codexHooksNeedReview(count): lang.t("doctor.finding.codexReview", count)
        }
    }

    static func testResult(_ result: HookRoundTripResult, lang: LanguageManager) -> String {
        guard let failure = result.failure else {
            return lang.t("doctor.test.passed")
        }

        switch failure {
        case .hookNotInConfig: return lang.t("doctor.test.failed.config")
        case .pluginOutdated: return lang.t("doctor.test.failed.plugin")
        case .binaryMissing: return lang.t("doctor.test.failed.binaryMissing")
        case .binaryNotExecutable: return lang.t("doctor.test.failed.binaryNotExecutable")
        case .binaryOutdated: return lang.t("doctor.test.failed.binaryOutdated")
        case .bridgeUnreachable: return lang.t("doctor.test.failed.bridge")
        case .bridgeUnexpectedReply: return lang.t("doctor.test.failed.bridgeReply")
        }
    }
}

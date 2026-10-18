import CoreGraphics
import Foundation
import Observation

/// Turns system events into cards for the notch: the charger being plugged in, the battery falling to the warning level. (Bluetooth
/// devices have their own monitor.) Nothing is shown for the state the app starts in, only for changes.
@MainActor
final class SystemEventMonitor {
    /// A card to show; `seconds` = nil keeps it until `onDismiss`.
    var onToast: ((SystemToast, Double?) -> Void)?
    var onDismiss: (() -> Void)?

    private let battery = BatteryMonitor.shared
    private var settings: AppSettings { .shared }
    private var last: BatteryMonitor.Reading?
    private var lowArmed = true
    private var lowShowing = false
    private var activityTask: Task<Void, Never>?

    func start() {
        last = battery.reading
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = battery.reading
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.batteryChanged()
                self?.observe()
            }
        }
    }

    private func batteryChanged() {
        guard let reading = battery.reading else { return }
        defer { last = reading }
        guard let previous = last else { return }
        if reading.pluggedIn || reading.charging {
            if lowShowing { dismissLow() }
            lowArmed = true
            if settings.chargingToast, !(previous.pluggedIn || previous.charging) { showCharging(reading) }
            return
        }
        // On battery: the warning fires once when the level reaches the threshold from above.
        let threshold = Int(settings.lowBatteryThreshold)
        if reading.percent > threshold { lowArmed = true }
        if lowShowing { updateLow(reading) }
        if settings.lowBatteryToast, lowArmed, reading.percent <= threshold, previous.percent > threshold || previous.pluggedIn {
            lowArmed = false
            showLow(reading)
        }
    }

    // MARK: Cards

    static func chargingToast(_ reading: BatteryMonitor.Reading) -> SystemToast {
        SystemToast(title: "充電中", subtitle: "已連接電源", progress: Double(reading.percent) / 100, tint: .green,
                    ringSymbol: "bolt.fill", trailing: .value("\(reading.percent)%"))
    }

    static func lowBatteryToast(_ reading: BatteryMonitor.Reading) -> SystemToast {
        SystemToast(title: "低電量", subtitle: "請盡快充電", progress: Double(reading.percent) / 100, tint: .red,
                    ringSymbol: nil, trailing: .value("\(reading.percent)%"), persistent: true)
    }

    private func showCharging(_ reading: BatteryMonitor.Reading) {
        onToast?(Self.chargingToast(reading), settings.chargingToastSeconds)
    }

    private func showLow(_ reading: BatteryMonitor.Reading) {
        lowShowing = true
        onToast?(Self.lowBatteryToast(reading), settings.lowBatteryDismissOnActivity ? nil : settings.chargingToastSeconds)
        if settings.lowBatteryDismissOnActivity { watchActivity() }
    }

    private func updateLow(_ reading: BatteryMonitor.Reading) {
        onToast?(Self.lowBatteryToast(reading), nil)
    }

    private func dismissLow() {
        lowShowing = false
        activityTask?.cancel()
        onDismiss?()
    }

    /// The warning stays while nobody is at the computer; it folds `lowBatteryActivityDelay` seconds after the user starts using it
    /// (moving the pointer, typing, clicking, scrolling).
    private func watchActivity() {
        activityTask?.cancel()
        activityTask = Task { [weak self] in
            // A moment first: the card must be seen even if the user was typing when it appeared.
            try? await Task.sleep(for: .seconds(1.2))
            var activeSince: Date?
            while !Task.isCancelled {
                guard let self, lowShowing else { return }
                if Self.secondsSinceLastInput() < 1 {
                    let since = activeSince ?? Date()
                    activeSince = since
                    if Date().timeIntervalSince(since) >= settings.lowBatteryActivityDelay {
                        dismissLow()
                        return
                    }
                } else {
                    activeSince = nil
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Time since the last mouse / keyboard / scroll event of the session.
    static func secondsSinceLastInput() -> TimeInterval {
        [CGEventType.mouseMoved, .leftMouseDown, .keyDown, .scrollWheel, .leftMouseDragged]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }
}

import Foundation
import IOKit.pwr_mgt

protocol SleepPreventionManaging: AnyObject {
    var state: SleepPreventionState { get }
    var onStateChange: ((SleepPreventionState) -> Void)? { get set }

    func start(mode: SleepPreventionMode, duration: SleepPreventionDuration, now: Date)
    func stop()
}

protocol PowerAssertionManaging {
    func create(type: String, name: String) -> IOPMAssertionID?
    func release(_ id: IOPMAssertionID)
}

struct IOKitPowerAssertionManager: PowerAssertionManaging {
    func create(type: String, name: String) -> IOPMAssertionID? {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &assertionID
        )
        return result == kIOReturnSuccess ? assertionID : nil
    }

    func release(_ id: IOPMAssertionID) {
        IOPMAssertionRelease(id)
    }
}

final class SleepPreventionManager: SleepPreventionManaging {
    private struct HeldAssertion {
        let id: IOPMAssertionID
        let type: String
    }

    private let assertionManager: PowerAssertionManaging
    private var heldAssertions: [HeldAssertion] = []
    private var expirationTask: Task<Void, Never>?

    private(set) var state: SleepPreventionState = .inactive {
        didSet {
            onStateChange?(state)
        }
    }

    var onStateChange: ((SleepPreventionState) -> Void)?

    init(assertionManager: PowerAssertionManaging = IOKitPowerAssertionManager()) {
        self.assertionManager = assertionManager
    }

    deinit {
        stop()
    }

    func start(mode: SleepPreventionMode, duration: SleepPreventionDuration, now: Date = Date()) {
        stop()

        let assertions = assertionTypes(for: mode).compactMap { type -> HeldAssertion? in
            guard let id = assertionManager.create(type: type, name: assertionName(for: type)) else { return nil }
            return HeldAssertion(id: id, type: type)
        }

        guard assertions.isEmpty == false else {
            state = .inactive
            return
        }

        heldAssertions = assertions
        let endsAt = duration.seconds.map { now.addingTimeInterval($0) }
        state = SleepPreventionState(mode: mode, duration: duration, startedAt: now, endsAt: endsAt)

        if let seconds = duration.seconds {
            expirationTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard Task.isCancelled == false else { return }
                await MainActor.run { [weak self] in
                    self?.stop()
                }
            }
        }
    }

    func stop() {
        expirationTask?.cancel()
        expirationTask = nil
        heldAssertions.forEach { assertionManager.release($0.id) }
        heldAssertions = []
        state = .inactive
    }

    func expireCurrentSessionForTesting() {
        stop()
    }

    private func assertionTypes(for mode: SleepPreventionMode) -> [String] {
        switch mode {
        case .display:
            return [kIOPMAssertionTypeNoDisplaySleep]
        case .system:
            return [kIOPMAssertionTypeNoIdleSleep]
        case .displayAndSystem:
            return [kIOPMAssertionTypeNoDisplaySleep, kIOPMAssertionTypeNoIdleSleep]
        }
    }

    private func assertionName(for type: String) -> String {
        if type == kIOPMAssertionTypeNoDisplaySleep {
            return "SleepGuard - Prevent Display Sleep"
        }
        return "SleepGuard - Prevent System Sleep"
    }
}

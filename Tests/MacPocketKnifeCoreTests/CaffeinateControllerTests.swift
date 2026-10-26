// Copyright 2026 Francisco Perdigon Romero and contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Testing
import MacPocketKnifeCore

@MainActor
private struct KeepAwakeFixture {
    let holder = FakeSleepAssertionHolder()
    let scheduler = FakeKeepAwakeScheduler()
    let store = FakeKeepAwakeStateStore()
    let controller: CaffeinateController

    init() {
        controller = CaffeinateController(holder: holder, scheduler: scheduler, store: store)
    }
}

@MainActor
private final class KeepAwakeEvents {
    var values: [Bool] = []
}

@Test @MainActor func convenienceControllersHaveExpectedNamesAndKinds() {
    let keepAwake = CaffeinateController.makeKeepAwake()
    #expect(keepAwake.name == CaffeinateController.assertionName)
    #expect(keepAwake.kind == .systemSleep)

    let keepUnlocked = CaffeinateController.makeKeepUnlocked()
    #expect(keepUnlocked.name == CaffeinateController.keepUnlockedAssertionName)
    #expect(keepUnlocked.kind == .displaySleep)
}

@Test @MainActor func keepAwakeActivatesIndefinitelyAndReleasesExactlyOnce() {
    let fixture = KeepAwakeFixture()
    let events = KeepAwakeEvents()
    fixture.controller.onChange = { events.values.append($0) }
    #expect(!fixture.controller.isActive)
    fixture.controller.activate()
    #expect(fixture.controller.isActive)
    #expect(fixture.controller.expiryDate == nil)
    #expect(fixture.holder.createdNames == ["MacPocketKnife keep-awake"])
    #expect(fixture.holder.createdKinds == [.systemSleep])
    #expect(fixture.store.state == KeepAwakeState(isActive: true))
    #expect(fixture.scheduler.pendingCount == 0)
    fixture.scheduler.advance(by: 1_000_000)
    #expect(fixture.controller.isActive)
    fixture.controller.deactivate()
    fixture.controller.deactivate()
    #expect(!fixture.controller.isActive)
    #expect(fixture.holder.releasedHandles == [SleepHandle(rawValue: 1)])
    #expect(fixture.store.state == nil)
    #expect(events.values == [true, false])
}

@Test @MainActor func keepAwakeToggleAcquiresAndReleases() {
    let fixture = KeepAwakeFixture()
    fixture.controller.toggle()
    #expect(fixture.controller.isActive)
    fixture.controller.toggle()
    #expect(!fixture.controller.isActive)
    fixture.controller.toggle()
    #expect(fixture.controller.isActive)
    #expect(fixture.holder.createdNames.count == 2)
    #expect(fixture.holder.releasedHandles.count == 1)
}

@Test @MainActor func keepAwakeDoubleActivationPreservesAssertionAndDeadline() {
    let fixture = KeepAwakeFixture()
    fixture.controller.activate(duration: 30)
    let expiry = fixture.controller.expiryDate
    fixture.controller.activate()
    fixture.controller.activate(duration: 300)
    #expect(fixture.holder.createdNames.count == 1)
    #expect(fixture.controller.expiryDate == expiry)
    #expect(fixture.scheduler.pendingCount == 1)
    fixture.scheduler.advance(by: 30)
    #expect(!fixture.controller.isActive)
    #expect(fixture.holder.releasedHandles.count == 1)
}

@Test @MainActor func keepAwakeExpiresAtTheInjectedDeadline() {
    let fixture = KeepAwakeFixture()
    let events = KeepAwakeEvents()
    fixture.controller.onChange = { events.values.append($0) }
    let expiry = fixture.scheduler.now.addingTimeInterval(60)
    fixture.controller.activate(duration: 60)
    #expect(fixture.store.state == KeepAwakeState(isActive: true, expiryDate: expiry))
    fixture.scheduler.advance(by: 59)
    #expect(fixture.controller.isActive)
    #expect(fixture.holder.releasedHandles.isEmpty)
    fixture.scheduler.advance(by: 1)
    #expect(!fixture.controller.isActive)
    #expect(fixture.controller.expiryDate == nil)
    #expect(fixture.store.state == nil)
    #expect(fixture.holder.releasedHandles.count == 1)
    #expect(events.values == [true, false])
    fixture.controller.deactivate()
    #expect(fixture.holder.releasedHandles.count == 1)
}

@Test @MainActor func keepAwakeCancelledExpiryCannotReleaseNewAssertion() {
    let fixture = KeepAwakeFixture()
    fixture.controller.activate(duration: 10)
    fixture.controller.deactivate()
    #expect(fixture.scheduler.pendingCount == 0)
    fixture.controller.activate()
    fixture.scheduler.advance(by: 10, includingCancelled: true)
    #expect(fixture.controller.isActive)
    #expect(fixture.holder.releasedHandles == [SleepHandle(rawValue: 1)])
    fixture.controller.deactivate()
    #expect(fixture.holder.releasedHandles == [SleepHandle(rawValue: 1), SleepHandle(rawValue: 2)])
}

@Test @MainActor func keepAwakeRestoresIndefiniteStateOnlyOnce() {
    let fixture = KeepAwakeFixture()
    fixture.store.state = KeepAwakeState(isActive: true)
    fixture.controller.restoreIfNeeded()
    fixture.controller.restoreIfNeeded()
    #expect(fixture.controller.isActive)
    #expect(fixture.controller.expiryDate == nil)
    #expect(fixture.holder.createdNames.count == 1)
    #expect(fixture.scheduler.pendingCount == 0)
}

@Test @MainActor func keepAwakeRestoresRemainingDuration() {
    let fixture = KeepAwakeFixture()
    let expiry = fixture.scheduler.now.addingTimeInterval(20)
    fixture.store.state = KeepAwakeState(isActive: true, expiryDate: expiry)
    fixture.controller.restoreIfNeeded()
    #expect(fixture.controller.isActive)
    #expect(fixture.controller.expiryDate == expiry)
    fixture.scheduler.advance(by: 19)
    #expect(fixture.controller.isActive)
    fixture.scheduler.advance(by: 1)
    #expect(!fixture.controller.isActive)
    #expect(fixture.holder.releasedHandles.count == 1)
    #expect(fixture.store.state == nil)
}

@Test(arguments: [-1.0, 0.0]) @MainActor func keepAwakeClearsExpiredState(offset: TimeInterval) {
    let fixture = KeepAwakeFixture()
    fixture.store.state = KeepAwakeState(
        isActive: true, expiryDate: fixture.scheduler.now.addingTimeInterval(offset)
    )
    fixture.controller.restoreIfNeeded()
    #expect(!fixture.controller.isActive)
    #expect(fixture.holder.createdNames.isEmpty)
    #expect(fixture.store.state == nil)
}

@Test @MainActor func keepAwakeRestoreWithNothingSavedDoesNothing() {
    let fixture = KeepAwakeFixture()
    fixture.controller.restoreIfNeeded()
    #expect(!fixture.controller.isActive)
    #expect(fixture.holder.createdNames.isEmpty)
    #expect(fixture.store.state == nil)
}

@Test @MainActor func keepAwakeDoesNotRestoreInactiveState() {
    let fixture = KeepAwakeFixture()
    fixture.store.state = KeepAwakeState(isActive: false)
    fixture.controller.restoreIfNeeded()
    #expect(!fixture.controller.isActive)
    #expect(fixture.holder.createdNames.isEmpty)
    #expect(fixture.store.state == nil)
}

@Test @MainActor func keepAwakeCreationFailureDoesNotPublishActiveState() {
    let holder = FakeSleepAssertionHolder(failsCreation: true)
    let scheduler = FakeKeepAwakeScheduler()
    let store = FakeKeepAwakeStateStore(state: KeepAwakeState(isActive: true))
    let controller = CaffeinateController(holder: holder, scheduler: scheduler, store: store)
    let events = KeepAwakeEvents()
    controller.onChange = { events.values.append($0) }
    controller.restoreIfNeeded()
    #expect(!controller.isActive)
    #expect(store.state == nil)
    #expect(scheduler.pendingCount == 0)
    #expect(events.values.isEmpty)
    controller.deactivate()
    #expect(holder.releasedHandles.isEmpty)
}

@Test(arguments: [0.0, -1.0, Double.infinity, Double.nan])
@MainActor func keepAwakeRejectsInvalidDuration(duration: TimeInterval) {
    let fixture = KeepAwakeFixture()
    fixture.controller.activate(duration: duration)
    #expect(!fixture.controller.isActive)
    #expect(fixture.holder.createdNames.isEmpty)
    #expect(fixture.store.state == nil)
}

@Test @MainActor func keepAwakeDestructionReleasesAssertionAndPreservesRestoration() {
    let holder = FakeSleepAssertionHolder()
    let scheduler = FakeKeepAwakeScheduler()
    let store = FakeKeepAwakeStateStore()
    var controller: CaffeinateController? = CaffeinateController(
        holder: holder, scheduler: scheduler, store: store
    )
    controller?.activate(duration: 60)
    controller = nil
    #expect(holder.releasedHandles == [SleepHandle(rawValue: 1)])
    #expect(scheduler.pendingCount == 0)
    #expect(store.state?.isActive == true)
}

@Test func iokitSleepAssertionHolderCreateAndReleaseDoesNotCrash() {
    let holder = IOKitSleepAssertionHolder()
    if let handle = holder.create(name: "MacPocketKnife keep-awake") {
        holder.release(handle)
    }
}

@Test @MainActor func keepUnlockedUsesDisplayAssertionAndRestoresItsDeadline() {
    let holder = FakeSleepAssertionHolder()
    let scheduler = FakeKeepAwakeScheduler()
    let store = FakeKeepAwakeStateStore()
    var controller: CaffeinateController? = CaffeinateController(
        holder: holder, scheduler: scheduler, store: store,
        name: CaffeinateController.keepUnlockedAssertionName, kind: .displaySleep
    )
    controller?.activate(duration: 60)
    #expect(holder.createdNames == ["MacPocketKnife keep-unlocked"])
    #expect(holder.createdKinds == [.displaySleep])
    controller = nil
    #expect(holder.releasedHandles.count == 1)
    scheduler.advance(by: 20)
    let restored = CaffeinateController(
        holder: holder, scheduler: scheduler, store: store,
        name: CaffeinateController.keepUnlockedAssertionName, kind: .displaySleep
    )
    restored.restoreIfNeeded()
    #expect(restored.isActive)
    #expect(restored.expiryDate == scheduler.now.addingTimeInterval(40))
    scheduler.advance(by: 40)
    #expect(!restored.isActive)
    #expect(store.state == nil)
    #expect(holder.createdKinds == [.displaySleep, .displaySleep])
    #expect(holder.releasedHandles.count == 2)
}

@Test @MainActor func controllerUsesConfiguredStateStoreKeyAndRestoresIndefinitely() {
    let key = "keepUnlockedTest-\(UUID().uuidString)"
    let defaults = UserDefaults.standard
    defer { defaults.removeObject(forKey: key) }
    let holder = FakeSleepAssertionHolder()
    let scheduler = FakeKeepAwakeScheduler()
    let controller = CaffeinateController(
        holder: holder, scheduler: scheduler,
        name: CaffeinateController.keepUnlockedAssertionName, kind: .displaySleep,
        stateStoreKey: key
    )
    controller.activate()
    let saved = UserDefaultsKeepAwakeStateStore(defaults: defaults, key: key)
    #expect(saved.load() == KeepAwakeState(isActive: true))
    let restored = CaffeinateController(
        holder: holder, scheduler: scheduler,
        name: CaffeinateController.keepUnlockedAssertionName, kind: .displaySleep,
        stateStoreKey: key
    )
    restored.restoreIfNeeded()
    #expect(restored.isActive)
    #expect(restored.expiryDate == nil)
    #expect(holder.createdKinds == [.displaySleep, .displaySleep])
    restored.deactivate()
    #expect(saved.load() == nil)
    #expect(controller.isActive)
    controller.deactivate()
}

@Test @MainActor func keepAwakeAndKeepUnlockedStoresAreIndependent() throws {
    let suite = "KeepUnlocked-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let awake = UserDefaultsKeepAwakeStateStore(defaults: defaults)
    let unlocked = UserDefaultsKeepAwakeStateStore(
        defaults: defaults, key: CaffeinateController.keepUnlockedStateKey
    )
    awake.save(KeepAwakeState(isActive: true))
    #expect(defaults.data(forKey: "keepAwakeState") != nil)
    #expect(unlocked.load() == nil)
    unlocked.save(KeepAwakeState(isActive: true, expiryDate: Date(timeIntervalSince1970: 100)))
    awake.save(nil)
    #expect(unlocked.load()?.expiryDate == Date(timeIntervalSince1970: 100))
    #expect(awake.load() == nil)
}

@Test func assertionHolderDefaultsToSystemSleepThroughProtocol() {
    let fake = FakeSleepAssertionHolder()
    let holder: any SleepAssertionHolding = fake
    let handle = holder.create(name: "Default assertion")
    #expect(handle != nil)
    #expect(fake.createdKinds == [.systemSleep])
    #expect(fake.createdNames == ["Default assertion"])
}

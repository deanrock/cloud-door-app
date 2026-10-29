//
//  WidgetDoorsTests.swift
//  CloudDoorKitTests
//

import Testing
@testable import CloudDoorKit

struct WidgetDoorsTests {
    let doors = [
        makeLocation(id: "a", name: "Front door"),
        makeLocation(id: "b", name: "Garage"),
        makeLocation(id: "c", name: "Gate"),
    ]

    @Test func resolveFindsTheConfiguredDoor() {
        let configured = DoorEntity(id: "b", name: "Garage")

        #expect(WidgetDoors.resolve(configured, in: doors)?.id == "b")
    }

    @Test func resolveShowsTheCurrentNameOfARenamedDoor() {
        let configured = DoorEntity(id: "b", name: "Old garage name")

        #expect(WidgetDoors.resolve(configured, in: doors)?.name == "Garage")
    }

    @Test func resolveGivesNilForADeletedDoor() {
        #expect(WidgetDoors.resolve(DoorEntity(id: "gone", name: "Gone"), in: doors) == nil)
    }

    @Test func resolveGivesNilWhenNothingIsConfigured() {
        #expect(WidgetDoors.resolve(nil, in: doors) == nil)
    }
}

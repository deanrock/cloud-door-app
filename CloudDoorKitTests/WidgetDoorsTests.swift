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

        #expect(WidgetDoors.resolve(configured, in: doors, signedIn: true)?.id == "b")
    }

    @Test func resolveShowsTheCurrentNameOfARenamedDoor() {
        let configured = DoorEntity(id: "b", name: "Old garage name")

        #expect(WidgetDoors.resolve(configured, in: doors, signedIn: true)?.name == "Garage")
    }

    @Test func resolveGivesNilForADeletedDoor() {
        #expect(WidgetDoors.resolve(DoorEntity(id: "gone", name: "Gone"), in: doors, signedIn: true) == nil)
    }

    @Test func signedOutIsReportedWhenNoAccountIsSaved() {
        let configuration = Configuration(store: FakeSecretStore())

        #expect(!WidgetDoors.isSignedIn(configuration))
    }

    @Test func pickerOffersAnExplanationInsteadOfAnEmptyList() {
        #expect(DoorQuery.search("", in: [], signedIn: false).map(\.name) == ["Sign In"])
        #expect(DoorQuery.search("gar", in: [], signedIn: true).map(\.name) == ["Open CloudDoor to load doors"])
    }

    @Test func pickerOffersTheDoorsWhenThereAreSome() {
        #expect(DoorQuery.search("", in: doors, signedIn: true).map(\.id) == ["a", "b", "c"])
        #expect(DoorQuery.search("gar", in: doors, signedIn: true).map(\.id) == ["b"])
    }

    @Test func resolveShowsSignInWhenSignedOutEvenIfADoorIsChosen() {
        let configured = DoorEntity(id: "b", name: "Garage")

        #expect(WidgetDoors.resolve(configured, in: doors, signedIn: false)?.name == "Sign In")
        #expect(WidgetDoors.resolve(nil, in: doors, signedIn: false) == nil)
    }

    @Test func resolveKeepsTheChoiceWhenTheDoorListIsEmpty() {
        let configured = DoorEntity(id: "b", name: "Garage")

        #expect(WidgetDoors.resolve(configured, in: [], signedIn: true)?.id == "b")
    }

    @Test func resolveGivesNilWhenNothingIsConfigured() {
        #expect(WidgetDoors.resolve(nil, in: doors, signedIn: true) == nil)
    }
}

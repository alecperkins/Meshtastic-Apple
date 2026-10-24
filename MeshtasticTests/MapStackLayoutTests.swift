// MapStackLayoutTests.swift
// MeshtasticTests
//
// Coverage for how the map fans out pins that share a position (`MapStackLayout`).
//
// Firmware position precision rounds nodes in an area onto the same point, so they stack exactly.
// The top pin stays on the true position, a few more peek out from behind it by a few screen
// points, and the top pin of a bigger stack shows the count.

import Testing
import Foundation
import CoreLocation
@testable import Meshtastic

@Suite("Map stacked-pin layout")
struct MapStackLayoutTests {

	private static let spotLatitudeI: Int32 = 407_100_000
	private static let spotLongitudeI: Int32 = -739_500_000

	private func snapshot(
		_ nodeNum: Int64,
		latitudeI: Int32 = spotLatitudeI,
		longitudeI: Int32 = spotLongitudeI,
		isOnline: Bool = false
	) -> MeshMapPositionSnapshot {
		MeshMapPositionSnapshot(
			id: nodeNum,
			coordinate: CLLocationCoordinate2D(latitude: Double(latitudeI) / 1e7, longitude: Double(longitudeI) / 1e7),
			latitudeI: latitudeI,
			longitudeI: longitudeI,
			precisionBits: 13,
			nodeNum: nodeNum,
			longName: "Node \(nodeNum)",
			shortName: "\(nodeNum)",
			isOnline: isOnline,
			viaMqtt: false,
			calculatedDelay: 0
		)
	}

	private func slots(_ snapshots: [MeshMapPositionSnapshot], activeNodeNum: Int64? = nil) -> [Int64: MapStackSlot] {
		let laidOut = MapStackLayout.assigningSlots(to: snapshots, activeNodeNum: activeNodeNum)
		var result: [Int64: MapStackSlot] = [:]
		for snap in laidOut {
			if let slot = snap.stackSlot { result[snap.nodeNum] = slot }
		}
		return result
	}

	// MARK: - Grouping

	@Test("Nodes on exactly the same position form one stack")
	func identicalPositionsStack() {
		let result = slots([snapshot(1), snapshot(2), snapshot(3)])
		#expect(Set(result.keys) == [1, 2, 3])
		#expect(result.values.allSatisfy { $0.count == 3 })
		#expect(Set(result.values.map(\.index)) == [0, 1, 2])
	}

	@Test("A node standing alone gets no slot")
	func loneNode() {
		let result = slots([snapshot(1), snapshot(2, latitudeI: Self.spotLatitudeI + 1)])
		#expect(result.isEmpty)
	}

	@Test("Nearby but different positions do not stack")
	func nearbyPositionsDoNotStack() {
		let result = slots([snapshot(1), snapshot(2), snapshot(3, longitudeI: Self.spotLongitudeI + 1)])
		#expect(Set(result.keys) == [1, 2])
	}

	@Test("Laying out keeps every snapshot, in order")
	func keepsSnapshots() {
		let input = [snapshot(3), snapshot(1, latitudeI: 1), snapshot(2)]
		let output = MapStackLayout.assigningSlots(to: input, activeNodeNum: nil)
		#expect(output.map(\.nodeNum) == [3, 1, 2])
		#expect(output[1].stackSlot == nil)
	}

	@Test("The same node appearing twice counts once and shares its slot")
	func duplicateNodeCountsOnce() {
		let laidOut = MapStackLayout.assigningSlots(to: [snapshot(1), snapshot(1), snapshot(2)], activeNodeNum: nil)
		#expect(laidOut.allSatisfy { $0.stackSlot?.count == 2 })
		#expect(laidOut[0].stackSlot == laidOut[1].stackSlot)
	}

	@Test("Duplicates of one node alone are not a stack")
	func duplicatesAloneAreNotAStack() {
		let laidOut = MapStackLayout.assigningSlots(to: [snapshot(0), snapshot(0)], activeNodeNum: nil)
		#expect(laidOut.allSatisfy { $0.stackSlot == nil })
	}

	@Test("Stacked pins are drawn at the shared position, not a fuzzed one")
	func stackedPinsShareThePosition() {
		var fuzzed = snapshot(2)
		fuzzed.coordinate = CLLocationCoordinate2D(latitude: fuzzed.coordinate.latitude + 0.00001, longitude: fuzzed.coordinate.longitude)
		let laidOut = MapStackLayout.assigningSlots(to: [snapshot(1), fuzzed], activeNodeNum: nil)
		#expect(laidOut[1].coordinate.latitude == Double(Self.spotLatitudeI) / 1e7)
		#expect(laidOut[1].coordinate.longitude == Double(Self.spotLongitudeI) / 1e7)
	}

	// MARK: - Order

	@Test("The connected node, then online nodes, then lower node numbers go on top")
	func topOrder() {
		let result = slots([snapshot(5), snapshot(4, isOnline: true), snapshot(9), snapshot(2)], activeNodeNum: 9)
		let order = result.sorted { $0.value.index < $1.value.index }.map(\.key)
		#expect(order == [9, 4, 2, 5])
	}

	// MARK: - Offsets and count

	@Test("The top pin stays on the true position and the next three peek out in different directions")
	func peekOffsets() {
		let offsets = (0..<MapStackLayout.maxVisible).map { MapStackLayout.offset(for: MapStackSlot(index: $0, count: 9)) }
		#expect(offsets[0] == .zero)
		#expect(offsets.dropFirst().allSatisfy { $0 != .zero })
		#expect(Set(offsets.map { "\($0.x),\($0.y)" }).count == offsets.count)
	}

	@Test("Pins past the visible few hide under the top one")
	func hiddenOffsets() {
		let hidden = (MapStackLayout.maxVisible..<9).map { MapStackLayout.offset(for: MapStackSlot(index: $0, count: 9)) }
		#expect(hidden.allSatisfy { $0 == .zero })
		#expect(MapStackLayout.offset(for: nil) == .zero)
	}

	@Test("Only the top of a stack too big to show carries the count")
	func showsCount() {
		#expect(!MapStackSlot(index: 0, count: MapStackLayout.maxVisible).showsCount)
		#expect(MapStackSlot(index: 0, count: MapStackLayout.maxVisible + 1).showsCount)
		#expect(!MapStackSlot(index: 1, count: MapStackLayout.maxVisible + 1).showsCount)
		#expect(MapStackSlot(index: 0, count: 7).shownCount == 7)
		#expect(MapStackSlot(index: 0, count: MapStackLayout.maxVisible).shownCount == nil)
	}

	@Test("The top of a stack draws above the rest of it")
	func drawRank() {
		let ranks = (0..<7).map { MapStackSlot(index: $0, count: 7).drawRank }
		#expect(ranks == ranks.sorted(by: >))
		#expect(ranks[0] > ranks[1])
	}
}

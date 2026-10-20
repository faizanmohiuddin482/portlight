import Foundation
import Testing
@testable import PortlightCore

private let a = ProcessIdentity(pid: 10, startTime: 1)
private let t0 = Date(timeIntervalSince1970: 1_000_000)
private let hour: TimeInterval = 3600

private func sample(_ id: ProcessIdentity = a, ports: [UInt16] = [3000], cpu: TimeInterval?) -> ActivitySample {
    ActivitySample(identity: id, ports: ports, cpuTime: cpu)
}

@Test func firstSightIsActive() {
    var t = ActivityTracker()
    t.record([sample(cpu: 5)], connections: [:], now: t0)
    #expect(t.lastActive(a) == t0)
}

@Test func connectionKeepsActive() {
    var t = ActivityTracker()
    t.record([sample(cpu: 5)], connections: [:], now: t0)
    t.record([sample(cpu: 5)], connections: [ConnectionKey(pid: 10, localPort: 3000): 1], now: t0 + hour)
    #expect(t.lastActive(a) == t0 + hour)
}

@Test func cpuGrowthKeepsActive() {
    var t = ActivityTracker()
    t.record([sample(cpu: 5)], connections: [:], now: t0)
    t.record([sample(cpu: 15)], connections: [:], now: t0 + hour)
    #expect(t.lastActive(a) == t0 + hour)
}

@Test func smallCpuTickIsIdle() {
    var t = ActivityTracker()
    t.record([sample(cpu: 5)], connections: [:], now: t0)
    t.record([sample(cpu: 5.5)], connections: [:], now: t0 + hour)
    #expect(t.lastActive(a) == t0)
}

@Test func idleAccumulatesAcrossSamples() {
    var t = ActivityTracker()
    t.record([sample(cpu: 5)], connections: [:], now: t0)
    for i in 1...10 { t.record([sample(cpu: 5 + Double(i) * 0.0001)], connections: [:], now: t0 + Double(i) * 15) }
    #expect(t.lastActive(a) == t0)
}

@Test func connectionOnOtherProcessIgnored() {
    var t = ActivityTracker()
    t.record([sample(cpu: 5)], connections: [:], now: t0)
    t.record([sample(cpu: 5)], connections: [ConnectionKey(pid: 99, localPort: 3000): 3], now: t0 + hour)
    #expect(t.lastActive(a) == t0)
}

@Test func forgetsGoneProcesses() {
    var t = ActivityTracker()
    t.record([sample(cpu: 5)], connections: [:], now: t0)
    t.record([], connections: [:], now: t0 + hour)
    #expect(t.lastActive(a) == nil)
}

@Test func pidReuseIsNewProcess() {
    var t = ActivityTracker()
    t.record([sample(cpu: 5)], connections: [:], now: t0)
    let reused = ProcessIdentity(pid: 10, startTime: 2)
    t.record([sample(reused, cpu: 0)], connections: [:], now: t0 + hour)
    #expect(t.lastActive(reused) == t0 + hour)
    #expect(t.lastActive(a) == nil)
}

import Foundation
import Darwin
import SystemMonitoring

@main @MainActor struct StabilityMonitorChecks {
    static func main() async throws {
        var count=0
        func check(_ condition:Bool,_ label:String) { precondition(condition,label);count += 1;print("PASS: "+label) }
        func settle(_ condition: ()->Bool) async {
            let deadline=Date().addingTimeInterval(5)
            while !condition() && Date()<deadline { try? await Task.sleep(nanoseconds:10_000_000) }
        }
        let base=FileManager.default.temporaryDirectory.appendingPathComponent("btt-monitor-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:base)}
        func directory(_ name:String) throws -> URL {
            let d=base.appendingPathComponent(name);try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true);return d
        }
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        func quotaEvent(reset:Date,shortReset:Date)->[String:Any] {
            ["timestamp":formatter.string(from:Date()),"payload":["type":"token_count","rate_limits":["limit_id":"codex","primary":["window_minutes":300,"used_percent":30,"resets_at":shortReset.timeIntervalSince1970],"secondary":["window_minutes":10080,"used_percent":49,"resets_at":reset.timeIntervalSince1970]]]]
        }
        func save(_ event:[String:Any],_ dir:URL)throws {
            try (JSONSerialization.data(withJSONObject:event)+Data([10])).write(to:dir.appendingPathComponent("rollout-fixture.jsonl"))
        }
        let expired=try directory("expired");try save(quotaEvent(reset:Date().addingTimeInterval(-1),shortReset:Date().addingTimeInterval(-1)),expired)
        let q=CodexQuotaMonitor(sessionDirectory:expired);var qChanged=false;q.onChange={qChanged=true}
        q.refresh();await settle {qChanged}
        check(q.snapshot.remainingPercent == nil && q.snapshot.awaitingReset && q.snapshot.touchBarText.contains("待更新"),"expired weekly quota never reports previous remaining")
        let quotaWindows = [
            CodexQuotaWindowSnapshot(label:"5小时",remainingPercent:79,resetAt:Date().addingTimeInterval(3600),resetText:"42分钟"),
            CodexQuotaWindowSnapshot(label:"7天",remainingPercent:75,resetAt:Date().addingTimeInterval(86400),resetText:"23小时"),
        ]
        let compactQuota = CodexQuotaSnapshot(remainingPercent:75,resetAt:nil,resetText:"",windowLabel:"7天",windows:quotaWindows,updatedAt:Date(),updatedAgeText:"刚刚",isStale:false)
        check(compactQuota.statusBarText.contains("5h余79%") && compactQuota.statusBarText.contains("重置") &&
              compactQuota.windowText.contains("42分钟") && compactQuota.touchBarText.contains("42分钟") &&
              !compactQuota.statusBarText.contains("42分钟"),"menu quota uses compact percentages while detailed and Touch Bar reset text stays intact")
        let staleQuota = CodexQuotaSnapshot(remainingPercent:75,resetAt:nil,resetText:"",windowLabel:"7天",windows:quotaWindows,updatedAt:Date().addingTimeInterval(-86400),updatedAgeText:"1天前",isStale:true)
        var awaitingQuota = CodexQuotaSnapshot.unavailable
        awaitingQuota.awaitingReset = true
        check(staleQuota.statusBarText.contains("旧") && staleQuota.statusBarText.contains("79%") &&
              awaitingQuota.statusBarText == "5h待更新 · 7d待更新" &&
              CodexQuotaSnapshot.unavailable.statusBarText == "5h -- · 7d --",
              "compact quota keeps stale, awaiting-reset, and unknown states distinct")
        let fixedTimezone = TimeZone(identifier:"Asia/Shanghai")!
        let fixedDateFormatter = ISO8601DateFormatter()
        func fixedDate(_ value:String) -> Date { fixedDateFormatter.date(from:value)! }
        func quotaWithReset(_ resetAt:Date?, stale:Bool = false) -> CodexQuotaSnapshot {
            CodexQuotaSnapshot(
                remainingPercent:65,
                resetAt:resetAt,
                resetText:"server countdown is not the status clock",
                windowLabel:"7天",
                windows:[
                    CodexQuotaWindowSnapshot(label:"5小时",remainingPercent:38,resetAt:resetAt,resetText:"server countdown"),
                    CodexQuotaWindowSnapshot(label:"7天",remainingPercent:65,resetAt:nil,resetText:""),
                ],
                updatedAt:fixedDate("2026-10-27T09:00:00+08:00"),
                updatedAgeText:"刚刚",
                isStale:stale
            )
        }
        let localMorning = fixedDate("2026-10-27T09:00:00+08:00")
        let sameDayClock = quotaWithReset(fixedDate("2026-10-27T15:30:00+08:00"))
        check(sameDayClock.statusBarText(now:localMorning,timeZone:fixedTimezone) == "5h余38%（15:30重置） · 7d余65%",
              "five-hour quota uses an absolute local reset clock on the same day")
        let nearMidnight = fixedDate("2026-10-27T22:30:00+08:00")
        let nextDayClock = quotaWithReset(fixedDate("2026-10-28T01:30:00+08:00"))
        check(nextDayClock.statusBarText(now:nearMidnight,timeZone:fixedTimezone).contains("（明日01:30重置）"),
              "reset tomorrow is labeled across local midnight")
        let laterDate = quotaWithReset(fixedDate("2026-10-30T03:00:00+08:00"))
        check(laterDate.statusBarText(now:localMorning,timeZone:fixedTimezone).contains("（10-30 03:00重置）"),
              "reset beyond tomorrow includes a month-day and local clock")
        let unknownClock = quotaWithReset(nil)
        check(unknownClock.statusBarText(now:localMorning,timeZone:fixedTimezone).contains("（重置未知）") &&
              unknownClock.windowText.contains("server countdown"),
              "unknown absolute reset stays explicit and does not parse countdown text")
        let pastReset = quotaWithReset(fixedDate("2026-10-27T08:59:00+08:00"),stale:true)
        check(pastReset.statusBarText(now:localMorning,timeZone:fixedTimezone) == "5h余38%（重置已过） · 7d余65%·旧",
              "expired stale reset is not shown as a future local clock")
        check(sameDayClock.statusBarText(now:localMorning,timeZone:fixedTimezone,scope:.fiveHour) == "5h余38%（15:30重置）" &&
              sameDayClock.statusBarText(now:localMorning,timeZone:fixedTimezone,scope:.sevenDay) == "7d余65%",
              "scoped status text renders each quota window independently")
        check(awaitingQuota.statusBarText(scope:.fiveHour) == "5h待更新" &&
              awaitingQuota.statusBarText(scope:.sevenDay) == "7d待更新" &&
              CodexQuotaSnapshot.unavailable.statusBarText(scope:.fiveHour) == "5h --" &&
              CodexQuotaSnapshot.unavailable.statusBarText(scope:.sevenDay) == "7d --",
              "scoped status text keeps awaiting and unknown states distinct per window")
        check(compactQuota.touchBarText(scope:.fiveHour).contains("5小时") && !compactQuota.touchBarText(scope:.fiveHour).contains("7天") &&
              compactQuota.touchBarText(scope:.sevenDay).contains("7天") && !compactQuota.touchBarText(scope:.sevenDay).contains("5小时"),
              "scoped touch bar text renders each quota window independently")
        let current=try directory("current");try save(quotaEvent(reset:Date().addingTimeInterval(0.8),shortReset:Date().addingTimeInterval(0.8)),current)
        let live=CodexQuotaMonitor(sessionDirectory:current);var liveChanged=false;live.onChange={liveChanged=true}
        live.refresh();await settle {liveChanged}
        check(live.snapshot.remainingPercent == 51,"current weekly quota remains supported")
        check(live.snapshot.windows.map(\.label) == ["5小时","7天"] && live.snapshot.windows.first?.remainingPercent == 70 && live.snapshot.touchBarText.contains("5小时"),"menu quota exposes both 5-hour/reset and 7-day windows")
        try await Task.sleep(nanoseconds:900_000_000);liveChanged=false;live.refresh();await settle{liveChanged}
        check(live.snapshot.awaitingReset && live.snapshot.remainingPercent == nil,"cached quota expires without a file change")
        let old=try directory("old")
        try save(["timestamp":formatter.string(from:Date().addingTimeInterval(-3600)),"type":"response_item","payload":["type":"function_call","name":"exec_command"]],old)
        let activity=CodexActivityMonitor(sessionDirectory:old);var changed=false;activity.onChange={changed=true}
        activity.refresh();await settle{changed}
        check(activity.snapshot.state == .stale && activity.snapshot.updatedAt.map { -$0.timeIntervalSinceNow>3590 } == true,"fractional event keeps its real age")
        let blocker=DispatchSemaphore(value:0)
        LocalJSONLFileSupport.queue.async {blocker.wait()}
        let stopped=CodexQuotaMonitor(sessionDirectory:current)
        let began=ProcessInfo.processInfo.systemUptime
        stopped.refresh();stopped.stop()
        check(ProcessInfo.processInfo.systemUptime-began < 0.05,"queued directory scan does not block MainActor")
        var responsive=false
        Task { @MainActor in responsive=true }
        try await Task.sleep(nanoseconds:30_000_000)
        check(responsive,"UI tasks run while background parsing is blocked")
        blocker.signal();try await Task.sleep(nanoseconds:100_000_000)
        check(stopped.snapshot == .unavailable,"late quota result cannot update stopped monitor")
        let executable=base.appendingPathComponent("tokens"), counter=base.appendingPathComponent("calls")
        try "#!/bin/sh\necho x >> '\(counter.path)'\nprintf '{\"rows\":[{\"date\":\"%s\",\"input\":123}]}' \"$(date +%Y-%m-%d)\"\n".write(to:executable,atomically:true,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
        let token=TokenUsageMonitor(cacheFile:base.appendingPathComponent("none"),openTokenURL:executable,eventLog:MonitorEventLog(url:base.appendingPathComponent("events.jsonl")))
        token.refresh(force:false);await settle{token.snapshot.tokens != nil}
        check(token.snapshot.tokens == 123,"token command completes with bounded runner")
        token.refresh(force:false);try await Task.sleep(nanoseconds:100_000_000)
        check((try String(contentsOf:counter,encoding:.utf8)).split(separator:"\n").count == 1,"automatic token refresh reuses two-minute cache")
        token.setEnabled(false);token.refresh();try await Task.sleep(nanoseconds:50_000_000)
        let disabledCalls = try String(contentsOf:counter,encoding:.utf8).split(separator:"\n").count
        check(token.snapshot.tokens == nil && disabledCalls == 1,"hidden token monitoring launches no process")
        token.setEnabled(true);await settle{token.snapshot.tokens != nil};token.stop()
        let enabledCalls = try String(contentsOf:counter,encoding:.utf8).split(separator:"\n").count
        check(token.snapshot.tokens == 123 && enabledCalls == 2,"reenabling starts a fresh sample")
        print("\(count) monitor stability checks passed")
    }
}

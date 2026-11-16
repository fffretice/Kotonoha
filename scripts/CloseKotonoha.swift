import AppKit
import Foundation
let apps=NSRunningApplication.runningApplications(withBundleIdentifier:"app.kotonoha.localtranslator")
for app in apps { _ = app.terminate() }
for _ in 0..<50 {
    if apps.allSatisfy({$0.isTerminated}) { break }
    RunLoop.current.run(until:Date().addingTimeInterval(0.1))
}
if apps.contains(where:{!$0.isTerminated}) {
    fputs("言叶仍在运行，请关闭后重试安装。\n",stderr);exit(2)
}
print("Closed existing Kotonoha instances")

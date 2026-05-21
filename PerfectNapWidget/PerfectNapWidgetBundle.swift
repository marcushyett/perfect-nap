import WidgetKit
import SwiftUI

@main
struct PerfectNapWidgetBundle: WidgetBundle {
    var body: some Widget {
        NapCountdownWidget()
        NapLockScreenLiveActivity()
    }
}

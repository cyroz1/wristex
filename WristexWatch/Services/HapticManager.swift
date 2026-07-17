import Foundation
#if canImport(WatchKit)
import WatchKit
#endif

public final class HapticManager {
    public static let shared = HapticManager()
    
    private init() {}
    
    public func playSuccess() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
    
    public func playFailure() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.failure)
        #endif
    }
    
    public func playClick() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
    
    public func playNotification() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }
    
    public func playStart() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.start)
        #endif
    }
    
    public func playStop() {
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.stop)
        #endif
    }
}

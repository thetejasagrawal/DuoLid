import Foundation
import IOKit
import IOKit.hid

let match = IOServiceMatching("IOHIDDevice")!
var iterator: io_iterator_t = 0
guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else {
    fatalError("Cannot enumerate HID devices")
}
defer { IOObjectRelease(iterator) }
var service = IOIteratorNext(iterator)
while service != 0 {
    let current = service
    service = IOIteratorNext(iterator)
    defer { IOObjectRelease(current) }
    func number(_ key: String) -> Int? {
        (IORegistryEntryCreateCFProperty(current, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
    }
    guard number("PrimaryUsagePage") == 32, number("PrimaryUsage") == 138 else { continue }
    guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, current) else { continue }
    print("Lid sensor found; product \(number("ProductID") ?? 0)")
    let opened = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    print("Open: \(opened)")
    guard opened == kIOReturnSuccess else { continue }
    defer { IOHIDDeviceClose(device, 0) }
    for kind in [kIOHIDReportTypeFeature, kIOHIDReportTypeInput] {
        var data = [UInt8](repeating: 0, count: 8)
        var length = data.count
        let result = IOHIDDeviceGetReport(device, kind, 1, &data, &length)
        print("Report \(kind.rawValue): result=\(result), bytes=\(Array(data.prefix(length)))")
    }
    IOHIDDeviceRegisterInputValueCallback(device, { _, result, _, value in
        let element = IOHIDValueGetElement(value)
        if IOHIDElementGetUsage(element) == 0x047f {
            print("Input callback: result=\(result), angle=\(IOHIDValueGetIntegerValue(value))")
        }
    }, nil)
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    CFRunLoopRunInMode(.defaultMode, 2, false)
    IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
}

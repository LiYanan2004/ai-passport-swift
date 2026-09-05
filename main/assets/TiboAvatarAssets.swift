final class TiboAvatarAssets {
    static let shared = TiboAvatarAssets()

    private let confirmedDescriptor: UnsafeMutablePointer<lv_image_dsc_t>
    private let announcedDescriptor: UnsafeMutablePointer<lv_image_dsc_t>
    private let idleDescriptor: UnsafeMutablePointer<lv_image_dsc_t>

    private init() {
        confirmedDescriptor = Self.makeDescriptor(
            start: passport_tibo_confirmed_data_start(),
            end: passport_tibo_confirmed_data_end()
        )
        announcedDescriptor = Self.makeDescriptor(
            start: passport_tibo_announced_data_start(),
            end: passport_tibo_announced_data_end()
        )
        idleDescriptor = Self.makeDescriptor(
            start: passport_tibo_idle_data_start(),
            end: passport_tibo_idle_data_end()
        )
    }

    func resolve(named name: String) -> UnsafeRawPointer? {
        if Self.matches(name, "tibo-reset-confirmed") {
            return UnsafeRawPointer(confirmedDescriptor)
        }
        if Self.matches(name, "tibo-reset-announced") {
            return UnsafeRawPointer(announcedDescriptor)
        }
        if Self.matches(name, "tibo-reset-idle") {
            return UnsafeRawPointer(idleDescriptor)
        }
        return nil
    }

    private static func matches(_ name: String, _ expectedName: StaticString) -> Bool {
        name.withCString { namePointer in
            strcmp(
                namePointer,
                UnsafePointer<CChar>(OpaquePointer(expectedName.utf8Start))
            ) == 0
        }
    }

    private static func makeDescriptor(
        start: UnsafePointer<UInt8>,
        end: UnsafePointer<UInt8>
    ) -> UnsafeMutablePointer<lv_image_dsc_t> {
        let descriptor = UnsafeMutablePointer<lv_image_dsc_t>.allocate(capacity: 1)
        passport_tibo_initialize_image_descriptor(
            descriptor,
            start,
            Int(bitPattern: end) - Int(bitPattern: start)
        )
        return descriptor
    }
}

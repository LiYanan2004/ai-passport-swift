final class Speaker {
    static let shared = Speaker()

    var volume: Int = 80 {
        didSet {
            let normalizedVolume = min(max(volume, 0), 100)
            if volume != normalizedVolume {
                volume = normalizedVolume
            }
            applyVolume()
        }
    }

    private init() {}

    func initialize() -> Bool {
        guard bsp_audio_init() == ESP_OK else {
            return false
        }
        applyVolume()
        return true
    }

    func setFormat(
        sampleRate: UInt32,
        bitsPerSample: UInt8,
        channelCount: UInt8
    ) -> esp_err_t {
        bsp_audio_set_format(sampleRate, bitsPerSample, channelCount)
    }

    func write(_ samples: UnsafeRawPointer, byteCount: Int) -> esp_err_t {
        bsp_audio_write(samples, byteCount)
    }

    private func applyVolume() {
        bsp_audio_set_volume(UInt8(volume))
    }
}

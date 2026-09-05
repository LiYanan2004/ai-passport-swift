final class Microphone {
    static let shared = Microphone()

    private init() {}

    func initialize() -> Bool {
        bsp_audio_init() == ESP_OK
    }

    func setFormat(
        sampleRate: UInt32,
        bitsPerSample: UInt8,
        channelCount: UInt8
    ) -> esp_err_t {
        bsp_audio_set_format(sampleRate, bitsPerSample, channelCount)
    }

    func read(_ samples: UnsafeMutableRawPointer, byteCount: Int) -> esp_err_t {
        bsp_audio_read(samples, byteCount)
    }
}

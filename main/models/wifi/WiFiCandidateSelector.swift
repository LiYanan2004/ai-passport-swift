struct WiFiCandidateSelector {
    private(set) var candidateIndex: Int?

    private var candidateCount = 0
    private var availability: [Bool]?

    init(candidateCount: Int = 0, availability: [Bool]? = nil) {
        reset(candidateCount: candidateCount, availability: availability)
    }

    var hasCandidate: Bool {
        candidateIndex != nil
    }

    mutating func reset(candidateCount: Int, availability: [Bool]? = nil) {
        self.candidateCount = candidateCount
        self.availability = availability
        candidateIndex = 0
        skipUnavailableCandidates()
    }

    @discardableResult
    mutating func advance() -> Bool {
        if let candidateIndex {
            self.candidateIndex = candidateIndex + 1
        }
        skipUnavailableCandidates()
        return hasCandidate
    }

    private mutating func skipUnavailableCandidates() {
        while let candidateIndex, candidateIndex < candidateCount {
            guard let availability else {
                return
            }
            if candidateIndex < availability.count, availability[candidateIndex] {
                return
            }
            self.candidateIndex = candidateIndex + 1
        }
        candidateIndex = nil
    }
}

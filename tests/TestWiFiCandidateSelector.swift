@main
struct WiFiCandidateSelectorTests {
    static func main() {
        var selector = WiFiCandidateSelector(candidateCount: 3)
        precondition(selector.candidateIndex == 0)
        precondition(selector.advance())
        precondition(selector.candidateIndex == 1)
        precondition(selector.advance())
        precondition(selector.candidateIndex == 2)
        precondition(!selector.advance())

        selector.reset(candidateCount: 0)
        precondition(!selector.hasCandidate)

        selector.reset(candidateCount: 2)
        precondition(selector.candidateIndex == 0)

        selector.reset(candidateCount: 4, availability: [false, true, false, true])
        precondition(selector.candidateIndex == 1)
        precondition(selector.advance())
        precondition(selector.candidateIndex == 3)
        precondition(!selector.advance())

        selector.reset(candidateCount: 2, availability: [false, false])
        precondition(!selector.hasCandidate)
    }
}

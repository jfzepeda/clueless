import Testing
@testable import clueless

struct AudioRouterTests {
    @Test func releasingHoldDoesNotStopPersistentListening() {
        var intent = ListeningIntent()
        intent.persistent = true
        intent.held = true
        intent.held = false
        #expect(intent.wanted)
        intent.stop()
        #expect(!intent.wanted)
    }

    @Test func temporaryListeningEndsOnRelease() {
        var intent = ListeningIntent()
        intent.held = true
        #expect(intent.wanted)
        intent.held = false
        #expect(!intent.wanted)
    }

    @Test func finalTranscriptReplacesDeltasAndIgnoresDuplicateEvents() {
        var history = TranscriptHistory()
        history.update(id: "a", text: "Hello", final: false)
        history.update(id: "a", text: " world", final: false)
        #expect(history.entries[0].text == "Hello world")
        history.update(id: "a", text: "Hello, world.", final: true)
        history.update(id: "a", text: "Hello, world.", final: true)
        history.update(id: "a", text: "late delta", final: false)
        #expect(history.entries.count == 1)
        #expect(history.confirmedText == "Hello, world.")
    }

    @Test func committedOrderSurvivesOutOfOrderCompletion() {
        var history = TranscriptHistory()
        history.order(id: "a", after: nil)
        history.order(id: "b", after: "a")
        history.update(id: "b", text: "Second", final: true)
        history.update(id: "a", text: "First", final: true)
        #expect(history.confirmedText == "First\nSecond")
    }

    @Test func provisionalTextDoesNotEnterAssistantContext() {
        var history = TranscriptHistory()
        history.update(id: "a", text: "Uncertain words", final: false)
        #expect(history.confirmedText.isEmpty)
    }

    @Test func silenceAfterSpeechCommitsOnce() {
        var vad = VoiceActivityDetector()
        let speech = vad.consume(duration: 0.5, isSpeech: true)
        let shortSilence = vad.consume(duration: 0.4, isSpeech: false)
        let endOfTurn = vad.consume(duration: 0.5, isSpeech: false)
        let followingSilence = vad.consume(duration: 0.5, isSpeech: false)
        #expect(speech == nil)
        #expect(shortSilence == nil)
        #expect(endOfTurn == .pause)
        #expect(followingSilence == nil)
    }

    @Test func musicAfterSpeechEndsTurnWithoutAmplitudeSilence() {
        var vad = VoiceActivityDetector()
        let speech = AudioPacket(pcm: .init(repeating: 0, count: 24000), level: 0.2, isSpeech: true)
        let music = AudioPacket(pcm: .init(repeating: 0, count: 24000), level: 0.6, isSpeech: false)
        #expect(vad.consume(duration: speech.duration, isSpeech: speech.isSpeech) == nil)
        #expect(vad.consume(duration: music.duration, isSpeech: music.isSpeech) == nil)
        #expect(vad.consume(duration: music.duration, isSpeech: music.isSpeech) == .pause)
        #expect(vad.consume(duration: music.duration, isSpeech: music.isSpeech) == nil)
    }

    @Test func musicAloneDoesNotStartSpokenTurn() {
        var vad = VoiceActivityDetector()
        #expect(vad.consume(duration: 15, isSpeech: false) == .durationLimit)
        #expect(!vad.heardSpeech)
        #expect(vad.consume(duration: 1, isSpeech: false) == nil)
    }

    @Test func longTurnIsBounded() {
        var vad = VoiceActivityDetector()
        let beforeLimit = vad.consume(duration: 14, isSpeech: true)
        let atLimit = vad.consume(duration: 1, isSpeech: true)
        #expect(beforeLimit == nil)
        #expect(atLimit == .durationLimit)
        #expect(vad.elapsed == 0)
    }

    @Test func audioDurationUsesPCM16Mono24kHz() {
        let packet = AudioPacket(pcm: .init(repeating: 0, count: 48000), level: 0, isSpeech: false)
        #expect(packet.duration == 1)
    }
    @Test func liveTranscriptionAndAutoAnswerBothSupportChat() {
        #expect(RouterMode.transcription.supportsChat)
        #expect(RouterMode.autoAnswer.supportsChat)
        #expect(!RouterMode.dictation.supportsChat)
        #expect(!RouterMode.virtualMicrophone.supportsChat)
    }

    @Test func previousAssistantPreferenceMigratesToAutoAnswer() {
        #expect(RouterMode.restored(from: "AI Assistant") == .autoAnswer)
        #expect(RouterMode.restored(from: "Auto Answer") == .autoAnswer)
        #expect(RouterMode.restored(from: "Live Transcription") == .transcription)
    }

    @Test func transportChunkDoesNotEndSpokenTurn() {
        var vad = VoiceActivityDetector()
        let chunk = vad.consume(duration: 15, isSpeech: true)
        let pause = vad.consume(duration: 0.9, isSpeech: false)
        #expect(chunk == .durationLimit)
        #expect(pause == .pause)
    }

    @Test func autoAnswerWaitsForPauseAndAllFinalTranscripts() {
        var turns = TranscriptionTurns()
        turns.register(id: "a", endsTurn: false)
        turns.register(id: "b", endsTurn: true)
        let secondFirst = turns.complete(id: "b", text: "second part")
        let completed = turns.complete(id: "a", text: "First part")
        let duplicate = turns.complete(id: "b", text: "second part")
        #expect(secondFirst.isEmpty)
        #expect(completed == ["First part second part"])
        #expect(duplicate.isEmpty)
    }

    @Test func eachPauseProducesOneTurnIncludingStatementsWithoutQuestions() {
        var turns = TranscriptionTurns()
        turns.register(id: "a", endsTurn: true)
        turns.register(id: "b", endsTurn: true)
        let later = turns.complete(id: "b", text: "The meeting ends at five.")
        let ordered = turns.complete(id: "a", text: "Explain the plan")
        #expect(later.isEmpty)
        #expect(ordered == ["Explain the plan", "The meeting ends at five."])
    }

    @Test func releaseFinishesAlreadyCommittedSpeechWithoutAnotherPause() {
        var turns = TranscriptionTurns()
        turns.register(id: "a", endsTurn: false)
        let beforeRelease = turns.complete(id: "a", text: "A long spoken turn")
        let afterRelease = turns.finishLastTurn()
        let duplicateRelease = turns.finishLastTurn()
        #expect(beforeRelease.isEmpty)
        #expect(afterRelease == ["A long spoken turn"])
        #expect(duplicateRelease.isEmpty)
    }

    @Test func emptyTurnsDoNotTriggerResponses() {
        var turns = TranscriptionTurns()
        turns.register(id: "a", endsTurn: true)
        let result = turns.complete(id: "a", text: "  ")
        #expect(result.isEmpty)
    }

}

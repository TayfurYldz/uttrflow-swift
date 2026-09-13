// Tests the home page, the menu bar and the clipboard panel while the speech model loads.
import Foundation
import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowUX

@Suite("Where a person would dictate, while the speech model loads")
struct SpeechModelLoadingSurfacesTests {
    /// The home page with every permission granted and the model at one point in its load.
    private func home(_ load: SpeechModelLoad?) -> HomePresentation {
        HomePresenter.page(
            for: HomeSnapshot(
                permissions: [.microphone: .granted, .accessibility: .granted],
                shortcut: "⌥Space", now: HistoryFixture.now, speechModel: load),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)
    }

    @Test("the home page shows a loading card while the model loads, and puts the ring out")
    func homeShowsTheLoad() throws {
        let page = home(.loading(elapsed: .seconds(1)))
        let notice = try #require(page.speechModel)

        #expect(notice.isLoading)
        #expect(notice.title == "Loading the speech model…")
        #expect(notice.action == nil)
        #expect(
            notice.accessibilityLabel
                == "Loading the speech model. Dictation starts working as soon as it’s ready.")
        #expect(!page.status.isReady)
        #expect(page.status.text == "Loading speech model")
        #expect(page.nextStep == nil, "the load card is the only card while nothing else blocks dictation")
    }

    @Test("the home page's card gains the minutes only once the load has run on")
    func homeEstimateWaits() throws {
        let early = try #require(home(.loading(elapsed: .seconds(3))).speechModel)
        let late = try #require(home(.loading(elapsed: .seconds(90))).speechModel)

        #expect(!early.message.contains("minute"))
        #expect(late.message.contains("2–3 minutes"))
    }

    @Test("the card is gone once the model has loaded")
    func homeClearsWhenLoaded() {
        let page = home(nil)

        #expect(page.speechModel == nil)
        #expect(page.status == HomeStatus(text: "Listening · ready", isReady: true))
        #expect(page.nextStep == nil)
    }

    @Test("a failed load shows a failed card with Try Again")
    func homeShowsTheFailure() throws {
        let page = home(.failed)
        let notice = try #require(page.speechModel)

        #expect(!notice.isLoading)
        #expect(notice.title == "The speech model didn’t load")
        #expect(notice.action == MainAction(title: "Try Again", intent: .recover(.retry)))
        #expect(page.status.text == "Speech model didn’t load")
    }

    @Test("a missing permission outranks the load, since it is the thing to fix first")
    func permissionOutranksTheLoad() {
        let page = HomePresenter.page(
            for: HomeSnapshot(
                permissions: [.microphone: .denied], shortcut: "⌥Space", now: HistoryFixture.now,
                speechModel: .loading(elapsed: .seconds(1))),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)

        #expect(page.speechModel == nil)
        #expect(page.status.text == "Not listening")
    }

    @Test("readiness tells the load from the injected clock, and nothing once ready")
    func readinessTimesTheLoad() {
        let clock = ManualClock()
        let started = clock.now
        clock.advance(by: .seconds(12))
        let now = clock.now

        #expect(
            SpeechModelReadiness.loading.load(since: started, now: now) == .loading(elapsed: .seconds(12)))
        #expect(SpeechModelReadiness.loading.load(since: nil, now: now) == .loading(elapsed: .zero))
        #expect(SpeechModelReadiness.loadFailed.load(since: started, now: now) == .failed)
        #expect(SpeechModelReadiness.ready.load(since: started, now: now) == nil)
        #expect(SpeechModelReadiness.notInstalled.load(since: started, now: now) == nil)
        #expect(
            SpeechModelReadiness.downloading(fractionCompleted: 0.5).load(since: started, now: now) == nil)
    }

    @Test("the menu bar names a failed load rather than calling setup unfinished")
    func menuBarNamesTheFailure() {
        let menu = MenuBarPresenter.present(MenuBarState(speechModel: .loadFailed))

        #expect(menu.statusLine == "Speech model didn't load")
        #expect(!MenuBarPresenter.canStartDictation(in: MenuBarState(speechModel: .loadFailed)))
    }

    @Test("the clipboard panel's microphone says loading, not downloading, during a load")
    func panelSaysLoading() {
        var snapshot = PanelFixture.panel()
        snapshot.dictation = .unavailable(.modelLoading)
        let mic = PanelPresenter.present(snapshot).microphone

        #expect(!mic.isEnabled)
        #expect(mic.label == "The speech model is still loading")
        #expect(mic.status == "Speech model still loading")
    }
}

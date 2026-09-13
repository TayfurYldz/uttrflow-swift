// Tests for the brand palette.

import Testing

@testable import Uttrflow

@Suite("The brand palette")
struct BrandPaletteTests {
    @Test("holds the primary teal and the secondary purple the brand is drawn in")
    func keyValues() {
        #expect(BrandPalette.Teal.primary == 0x29_C0B4)
        #expect(BrandPalette.Purple.secondary == 0x61_399F)
        #expect(BrandPalette.Purple.secondaryMiddle == 0x3E_368A)
        #expect(BrandPalette.Purple.secondaryEnd == 0x2A_5B72)
    }

    @Test("a fixed tone carries the same value in both appearances")
    func fixedTone() {
        let tone = BrandTone(0x12_151C)

        #expect(tone.dark == 0x12_151C)
        #expect(tone.light == 0x12_151C)
    }

    @Test("a pair that shares a member with the ramp points at that member")
    func pairsReuseTheRamp() {
        #expect(BrandPalette.Teal.ink.dark == BrandPalette.Teal.bright)
        #expect(BrandPalette.Teal.calloutWash.light == BrandPalette.Teal.wash)
        #expect(BrandPalette.Surface.control.dark == BrandPalette.Surface.raised)
        #expect(BrandPalette.Surface.onboardingControl.dark == BrandPalette.Surface.raised)
    }
}

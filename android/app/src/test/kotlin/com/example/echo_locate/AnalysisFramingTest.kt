package com.example.echo_locate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the sign reader is actually fed, checked on the desk.
 *
 * The failure these guard against is silent and looks like nothing at all: ML
 * Kit returns no text, the leg never advances on a sign, and the walker is
 * asked to confirm every landmark by hand. Nothing logs an error — the OCR
 * line just reads `lines=0` forever. On a device that takes a corridor walk to
 * reproduce; here it takes a second.
 */
class AnalysisFramingTest {

    /** The configs a mid-range phone typically offers ARCore. */
    private fun typicalOptions() = listOf(
        CameraOption(cpuWidth = 640, cpuHeight = 480, gpuWidth = 1920, gpuHeight = 1080),
        CameraOption(cpuWidth = 1280, cpuHeight = 960, gpuWidth = 1920, gpuHeight = 1080),
        CameraOption(cpuWidth = 1920, cpuHeight = 1080, gpuWidth = 1920, gpuHeight = 1080),
    )

    @Test
    fun `the largest cpu image inside the budget wins`() {
        val chosen = AnalysisFraming.pickCamera(typicalOptions())
        assertEquals(1280, chosen?.cpuWidth)
        assertEquals(960, chosen?.cpuHeight)
    }

    @Test
    fun `a bigger viewfinder breaks a tie between equal cpu images`() {
        val chosen = AnalysisFraming.pickCamera(
            listOf(
                CameraOption(cpuWidth = 1280, cpuHeight = 960, gpuWidth = 1280, gpuHeight = 720),
                CameraOption(cpuWidth = 1280, cpuHeight = 960, gpuWidth = 1920, gpuHeight = 1080),
            )
        )
        assertEquals(1920, chosen?.gpuWidth)
    }

    @Test
    fun `a phone that only offers huge cpu images gets the smallest of them`() {
        val chosen = AnalysisFraming.pickCamera(
            listOf(
                CameraOption(cpuWidth = 3840, cpuHeight = 2160, gpuWidth = 1920, gpuHeight = 1080),
                CameraOption(cpuWidth = 1920, cpuHeight = 1080, gpuWidth = 1920, gpuHeight = 1080),
            )
        )
        assertEquals(1920, chosen?.cpuWidth)
    }

    @Test
    fun `no options is not a crash`() {
        assertNull(AnalysisFraming.pickCamera(emptyList()))
    }

    @Test
    fun `a frame already inside the budget is not cropped`() {
        val crop = AnalysisFraming.centreCrop(640, 480, targetPixels = 307_200)
        assertEquals(CropRect(0, 0, 640, 480), crop)
    }

    @Test
    fun `a quarter of the pixels is half of each side, centred`() {
        val crop = AnalysisFraming.centreCrop(1280, 960, targetPixels = 307_200)
        assertEquals(CropRect(x = 320, y = 240, width = 640, height = 480), crop)
    }

    /**
     * NV21 subsamples chroma two-by-two, so an odd offset or size shears the
     * colour planes against the luma one. ML Kit reads luminance, so the
     * result is not a colourful mess that somebody notices — it is a subtly
     * wrong image that reads slightly worse, which is the kind of bug that
     * survives a demo.
     */
    @Test
    fun `every crop is even on all four numbers`() {
        for (width in listOf(1279, 1280, 1281, 1600)) {
            for (height in listOf(959, 960, 961, 1200)) {
                val crop = AnalysisFraming.centreCrop(width, height, targetPixels = 320_000)
                assertTrue("x ${crop.x}", crop.x % 2 == 0)
                assertTrue("y ${crop.y}", crop.y % 2 == 0)
                assertTrue("w ${crop.width}", crop.width % 2 == 0)
                assertTrue("h ${crop.height}", crop.height % 2 == 0)
                assertTrue("fits", crop.x + crop.width <= width)
                assertTrue("fits", crop.y + crop.height <= height)
            }
        }
    }

    /**
     * The whole point of the crop: the same pixel count into ML Kit, taken
     * from a bigger sensor image, is more pixels on the sign the walker is
     * pointing at.
     */
    @Test
    fun `cropping keeps the cost the same and doubles the detail`() {
        val crop = AnalysisFraming.centreCrop(1280, 960, targetPixels = 307_200)
        assertEquals(307_200, crop.width * crop.height)
    }

    /**
     * The two analysers want opposite things from the same sensor image.
     *
     * Sign reading wants magnification and does not care about the edges of
     * the frame — the plate is in the middle, because that is where the walker
     * is pointing. Obstacle detection wants the edges above all: it reports
     * "on your left" and "on your right" by where a box falls across the
     * width, so a cropped frame would quietly stop warning about the trolley
     * beside the walker. It can afford to lose detail instead.
     */
    @Test
    fun `sign reading gets the middle of the frame at full detail`() {
        val framing = AnalysisFraming.framingFor(1280, 960, wantsText = true)
        assertEquals(1, framing.step)
        assertEquals(CropRect(x = 320, y = 240, width = 640, height = 480), framing.crop)
        assertEquals(640, framing.outWidth)
        assertEquals(480, framing.outHeight)
    }

    @Test
    fun `obstacle detection keeps the whole field of view`() {
        val framing = AnalysisFraming.framingFor(1280, 960, wantsText = false)
        assertEquals(CropRect(x = 0, y = 0, width = 1280, height = 960), framing.crop)
        assertEquals(2, framing.step)
        assertEquals(640, framing.outWidth)
        assertEquals(480, framing.outHeight)
    }

    /** Both analysers cost what they always cost, whatever the sensor gives. */
    @Test
    fun `neither analyser is handed more pixels than the budget`() {
        for (wantsText in listOf(true, false)) {
            for ((width, height) in listOf(640 to 480, 1280 to 960, 1279 to 959, 1600 to 1200)) {
                val framing = AnalysisFraming.framingFor(width, height, wantsText)
                assertTrue(
                    "$width x $height text=$wantsText gave ${framing.outWidth}x${framing.outHeight}",
                    framing.outWidth * framing.outHeight <= AnalysisFraming.TARGET_ANALYSIS_PIXELS,
                )
                assertTrue("even w", framing.outWidth % 2 == 0)
                assertTrue("even h", framing.outHeight % 2 == 0)
                assertTrue("fits", framing.crop.x + framing.crop.width <= width)
                assertTrue("fits", framing.crop.y + framing.crop.height <= height)
            }
        }
    }

    @Test
    fun `a small frame is left alone for both analysers`() {
        for (wantsText in listOf(true, false)) {
            val framing = AnalysisFraming.framingFor(640, 480, wantsText)
            assertEquals(1, framing.step)
            assertEquals(CropRect(0, 0, 640, 480), framing.crop)
        }
    }
}

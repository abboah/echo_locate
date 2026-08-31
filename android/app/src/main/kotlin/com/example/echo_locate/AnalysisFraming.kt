package com.example.echo_locate

import kotlin.math.roundToInt
import kotlin.math.sqrt

/** One of ARCore's camera configs, reduced to the four numbers that decide it. */
data class CameraOption(
    val cpuWidth: Int,
    val cpuHeight: Int,
    val gpuWidth: Int,
    val gpuHeight: Int,
) {
    val cpuPixels: Int get() = cpuWidth * cpuHeight
    val gpuPixels: Int get() = gpuWidth * gpuHeight
}

/** A rectangle of a camera image, in pixels. */
data class CropRect(val x: Int, val y: Int, val width: Int, val height: Int)

/**
 * How one camera image is cut down before it is handed to an analyser.
 *
 * [crop] is the part of the sensor image taken, and [step] is how many of its
 * pixels are skipped per output pixel — 1 for every pixel, 2 for every other.
 * Together they are the two ways of spending the same budget: [crop] buys
 * magnification at the cost of field of view, [step] buys field of view at the
 * cost of detail.
 */
data class Framing(val crop: CropRect, val step: Int) {
    val outWidth: Int get() = crop.width / step
    val outHeight: Int get() = crop.height / step
}

/**
 * What reaches ML Kit, and at what magnification.
 *
 * ## The bug this exists for
 *
 * ARCore gives a session two images: a GPU texture for the viewfinder and a
 * CPU image for whoever wants the pixels. Only the CPU one reaches ML Kit, and
 * the chooser used to take the **smallest** CPU config on offer while
 * tie-breaking toward the **largest** GPU texture — so the phone rendered a
 * 1920x1080 viewfinder and handed 640x480 to the thing this app actually
 * navigates by. A door plate at three or four metres is a handful of pixels
 * there, well under the ~16 px of text height ML Kit's Latin recogniser wants.
 * It read nothing, so no leg ever advanced on a sign, so the walker was asked
 * to confirm every landmark by hand.
 *
 * ## Why a bigger image and then a crop, rather than just a bigger image
 *
 * ML Kit's cost is per pixel, and so is the NV21 conversion that feeds it —
 * which runs on the thread that has to keep the camera moving. Quadrupling the
 * image quadruples both.
 *
 * The sign is in the middle of the frame, because the walker is pointing the
 * phone down the corridor at it and the arrow is drawn there too. So the frame
 * is taken larger from the sensor and then cut down to the same pixel count
 * the old path spent — [TARGET_ANALYSIS_PIXELS]. Identical cost, twice the
 * angular resolution on the thing being read, which is roughly twice the
 * distance a plate can be read from.
 *
 * The crop applies to sign reading only. Obstacle detection reads positions
 * across the whole field of view — `DetectionService` calls anything past 0.65
 * of the width "on your right" — so cropping its frames would quietly narrow
 * what a blind walker is warned about. See `analyse`.
 */
object AnalysisFraming {

    /**
     * The largest CPU image worth accepting, in pixels.
     *
     * Sized to admit 1280x960 and refuse 1920x1080. The cap is not about ML
     * Kit — the crop below fixes its cost at [TARGET_ANALYSIS_PIXELS] whatever
     * arrives — it is about the per-frame NV21 conversion, which is a
     * row-by-row copy of the whole image on the render thread.
     */
    const val MAX_CPU_PIXELS = 1_310_720

    /**
     * How many pixels ML Kit is given, whatever the sensor delivers.
     *
     * 640x480: exactly what the old path spent, so this change is free at the
     * point where cost is measured. Raise it only against measured frame
     * times on the hardware this targets.
     */
    const val TARGET_ANALYSIS_PIXELS = 307_200

    /**
     * The config to run the session at, or null when there are none to pick
     * from.
     *
     * The largest CPU image inside the budget, because that is the one the
     * sign reader gets the most out of; the larger viewfinder breaks a tie,
     * which is the one part of the old rule worth keeping. A phone that offers
     * nothing inside the budget gets the smallest it has rather than nothing:
     * an oversized frame costs milliseconds, and refusing to choose costs the
     * whole feature.
     */
    fun pickCamera(
        options: List<CameraOption>,
        maxCpuPixels: Int = MAX_CPU_PIXELS,
    ): CameraOption? {
        if (options.isEmpty()) return null
        val affordable = options.filter { it.cpuPixels <= maxCpuPixels }
        if (affordable.isNotEmpty()) {
            return affordable.maxWith(compareBy({ it.cpuPixels }, { it.gpuPixels }))
        }
        return options.minWith(compareBy({ it.cpuPixels }, { -it.gpuPixels }))
    }

    /**
     * The middle [targetPixels] of a [width] x [height] image.
     *
     * Every number comes back even. NV21 subsamples chroma two-by-two, so an
     * odd offset or an odd size shears the colour planes against the luma one
     * — which ML Kit does not report as an error because it reads luminance,
     * it just reads slightly worse.
     */
    fun centreCrop(
        width: Int,
        height: Int,
        targetPixels: Int = TARGET_ANALYSIS_PIXELS,
    ): CropRect {
        if (width * height <= targetPixels) return CropRect(0, 0, width, height)

        val scale = sqrt(targetPixels.toDouble() / (width.toDouble() * height))
        val cropWidth = even((width * scale).roundToInt()).coerceIn(2, even(width))
        val cropHeight = even((height * scale).roundToInt()).coerceIn(2, even(height))
        return CropRect(
            x = even((width - cropWidth) / 2),
            y = even((height - cropHeight) / 2),
            width = cropWidth,
            height = cropHeight,
        )
    }

    /**
     * How to cut a [width] x [height] sensor image down for one analyser.
     *
     * ## Why the two analysers are framed differently
     *
     * They want opposite things, and giving both the same frame is what made
     * the old choice look reasonable — one image, so pick the small one and be
     * done.
     *
     * **Sign reading** wants magnification. The plate is in the middle of the
     * frame because that is where the walker is pointing the phone and where
     * the arrow is drawn, and the edges hold corridor. So it gets a centre
     * crop at full sensor detail.
     *
     * **Obstacle detection** wants the edges above all else. It reports
     * position by where a box falls across the width — past 0.65 is "on your
     * right" — so a cropped frame would stop it warning about the trolley
     * beside the walker, silently, which is the one failure in this app with a
     * physical consequence. It gets the whole field of view and gives up
     * detail instead: a box only has to be found, not read.
     *
     * Both land inside [targetPixels], so both cost what they always cost
     * however large an image the sensor is now delivering.
     */
    fun framingFor(
        width: Int,
        height: Int,
        wantsText: Boolean,
        targetPixels: Int = TARGET_ANALYSIS_PIXELS,
    ): Framing {
        if (wantsText) {
            return Framing(centreCrop(width, height, targetPixels), step = 1)
        }

        var step = 1
        while ((width / step) * (height / step) > targetPixels) step++

        // Trimmed to a whole number of output pixels, and to an even number of
        // them: NV21's chroma is subsampled two-by-two, so an odd output
        // dimension has half a chroma row at the edge.
        val block = 2 * step
        val cropWidth = (width / block) * block
        val cropHeight = (height / block) * block
        return Framing(
            CropRect(
                x = even((width - cropWidth) / 2),
                y = even((height - cropHeight) / 2),
                width = cropWidth,
                height = cropHeight,
            ),
            step = step,
        )
    }

    /** [value] rounded down to an even number. */
    private fun even(value: Int): Int = value and 1.inv()
}

# Audio Engine Implementation

This document explains the implementation of the Audio Engine task in EchoLocate, covering the "why" and "how" of the audio playback and recording functionality.

## Overview

The Audio Engine is responsible for:
- Generating and playing acoustic chirp signals through the device speaker
- Recording the echo response via the microphone
- Providing the recorded audio data for DSP processing

## Why This Implementation?

### Playback (flutter_soloud)
- **Why flutter_soloud?** It's a cross-platform audio engine that provides low-latency playback capabilities, essential for precise timing in acoustic measurements.
- **Why not other options?** Alternatives like `audioplayers` or `just_audio` don't offer the same level of control over audio data and timing required for scientific audio applications.
- **Key requirements:** Ability to play programmatically generated audio samples with exact timing.

### Recording (record package)
- **Why record package?** Provides cross-platform microphone access with configurable sample rates and formats, necessary for capturing high-quality audio data.
- **Why not flutter_soloud?** The flutter_soloud library focuses on playback; it doesn't provide microphone recording capabilities.
- **Key requirements:** Real-time audio capture at specific sample rates (44.1kHz) with low latency.

### WAV Format Conversion
- **Why WAV?** flutter_soloud requires audio data in file format; WAV is a simple, uncompressed format that preserves our generated float samples accurately.
- **Why not other formats?** MP3/AAC compression would introduce artifacts that could interfere with correlation analysis.
- **Implementation:** Custom WAV writer converts Float32List samples to 16-bit PCM WAV data in memory.

## How It Works

### 1. Initialization
```dart
await _soLoud.init();  // Initialize SoLoud engine
```

### 2. Chirp Generation & Playback
1. **Generate chirp:** Use `ChirpGenerator` to create FMCW sweep from 1kHz to 5kHz over 100ms
2. **Convert to WAV:** Transform Float32List samples to WAV format in memory
3. **Load & play:** Use `SoLoud.loadMem()` to load WAV data, then `play()` to emit through speaker

### 3. Echo Recording
1. **Start stream:** Use `AudioRecorder.startStream()` with PCM16 config at 44.1kHz
2. **Capture data:** Listen to the stream and collect Int16 samples
3. **Normalize:** Convert to double values in range [-1.0, 1.0]
4. **Duration control:** Record for exactly the specified milliseconds

### 4. Data Flow
```
ChirpGenerator → Float32List → WAV → SoLoud → Speaker
Microphone → AudioRecorder → Int16List → Double List → DSP
```

## Technical Details

### Sample Rate & Format
- **Sample Rate:** 44.1kHz (CD quality, matches AppConstants.sampleRate)
- **Format:** 16-bit PCM (industry standard for audio processing)
- **Channels:** Mono (sufficient for distance measurement)

### Timing Considerations
- **Playback timing:** SoLoud provides reliable timing for short audio clips
- **Recording delay:** Account for system latency in measurement calculations
- **Synchronization:** Emit chirp, then immediately start recording to capture echo

### Memory Management
- **In-memory WAV:** No file I/O for faster operation
- **Stream processing:** Process audio data as it arrives to minimize memory usage
- **Resource cleanup:** Proper disposal of SoLoud and AudioRecorder instances

## Error Handling

### Permission Management
- Check microphone permissions before recording
- Handle permission denial gracefully with user feedback

### Audio Engine Failures
- Catch SoLoud initialization errors
- Handle playback failures (e.g., no audio device)
- Log all errors for debugging

### Data Validation
- Verify recorded sample count matches expected duration
- Check for empty or corrupted audio data
- Validate sample rate consistency

## Performance Considerations

### Latency
- **Target:** <10ms total system latency for accurate measurements
- **Playback:** SoLoud optimized for low-latency output
- **Recording:** Stream-based capture minimizes buffering delays

### CPU Usage
- **DSP:** Heavy computation in separate isolates when possible
- **Audio processing:** Efficient algorithms to avoid blocking UI
- **Memory:** Reuse buffers and dispose resources promptly

## Testing Strategy

### Unit Tests
- Mock audio engines for deterministic testing
- Test WAV conversion accuracy
- Verify sample normalization

### Integration Tests
- End-to-end chirp emission and recording
- Timing accuracy validation
- Cross-platform compatibility

### Manual Testing
- Audio output quality verification
- Microphone input level checking
- Distance measurement accuracy in real environments

## Future Enhancements

### Advanced Features
- **Multiple frequencies:** Support for different chirp patterns
- **Noise cancellation:** Advanced filtering for cleaner signals
- **Calibration:** Automatic gain adjustment for consistent measurements

### Performance Optimizations
- **Native code:** Move DSP to platform-specific implementations
- **Hardware acceleration:** Use device-specific audio processing
- **Streaming optimization:** Reduce memory allocation in hot paths

## Dependencies

- `flutter_soloud: ^2.0.0` - Cross-platform audio playback
- `record: ^6.0.0` - Cross-platform audio recording
- Custom WAV conversion (no external dependencies)

## Integration Points

- **DSP Pipeline:** Provides raw audio data to `CrossCorrelationService`
- **Measurement Controller:** Called by `MeasurementController.measureDistance()`
- **UI Feedback:** Reports recording/playback status for user interface updates

This implementation provides a solid foundation for acoustic distance measurement while maintaining cross-platform compatibility and performance requirements.
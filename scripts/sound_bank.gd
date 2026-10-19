class_name SoundBank
extends RefCounted
## Generated once per event, cached thereafter. Noise uses its own seeded RNG.
const PRESETS := {
	"swing": {"wave": "noise", "hz": 1800.0, "duration": 0.10, "volume": 0.20, "slide": -0.85, "attack": 0.004, "decay": 2.8},
	"hit": {"wave": "saw", "hz": 260.0, "duration": 0.09, "volume": 0.12, "slide": -0.7, "attack": 0.002, "decay": 2.0},
	"block": {"wave": "square", "hz": 720.0, "duration": 0.12, "volume": 0.16, "slide": -0.45, "attack": 0.001, "decay": 2.8},
	"heal": {"wave": "chime", "hz": 520.0, "duration": 0.24, "volume": 0.08, "slide": 0.5, "attack": 0.008, "decay": 2.8},
	"heal_charge": {"wave": "chime", "hz": 240.0, "duration": 1.0, "volume": 0.08, "slide": 1.2, "attack": 0.15, "decay": 0.6},
	"heal_interrupt": {"wave": "square", "hz": 360.0, "duration": 0.15, "volume": 0.10, "slide": -0.75, "attack": 0.002, "decay": 2.0},
	"hurt": {"wave": "square", "hz": 150.0, "duration": 0.22, "volume": 0.11, "slide": -0.8, "attack": 0.005, "decay": 1.8},
	"dash": {"wave": "noise", "hz": 900.0, "duration": 0.17, "volume": 0.17, "slide": 1.4, "attack": 0.015, "decay": 2.0},
	"reward": {"wave": "chime", "hz": 660.0, "duration": 0.40, "volume": 0.14, "slide": 0.4, "attack": 0.008, "decay": 2.4},
	"clear": {"wave": "chime", "hz": 440.0, "duration": 0.28, "volume": 0.12, "slide": 0.5, "attack": 0.01, "decay": 2.0},
	"boss": {"wave": "saw", "hz": 62.0, "duration": 1.3, "volume": 0.15, "slide": -0.35, "attack": 0.12, "decay": 1.4},
	"cast": {"wave": "square", "hz": 180.0, "duration": 0.30, "volume": 0.08, "slide": 0.7, "attack": 0.02, "decay": 2.0},
	"descend": {"wave": "chime", "hz": 330.0, "duration": 0.45, "volume": 0.13, "slide": -0.4, "attack": 0.02, "decay": 2.0},
	"death": {"wave": "square", "hz": 100.0, "duration": 0.65, "volume": 0.12, "slide": -0.85, "attack": 0.01, "decay": 2.0},
	"heartbeat": {"wave": "sine", "hz": 58.0, "duration": 0.20, "volume": 0.14, "slide": -0.15, "attack": 0.012, "decay": 3.0},
	"victory": {"wave": "chime", "hz": 523.25, "duration": 1.6, "volume": 0.15, "slide": 0.0, "attack": 0.02, "decay": 1.5},
}
var cache: Dictionary = {}

func stream_for(event: String) -> AudioStreamWAV:
	if cache.has(event): return cache[event]
	var preset: Dictionary = PRESETS[event]
	var rate := 22050
	var count := int(rate * preset.duration)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = event.hash()
	var phase := 0.0
	var filtered := 0.0
	for i in count:
		var seconds := float(i) / rate
		var t := float(i) / count
		var hz: float = preset.hz * maxf(0.05, 1.0 + preset.slide * t)
		phase += TAU * hz / rate
		var wave := 0.0
		match preset.wave:
			"square": wave = (1.0 if sin(phase) >= 0 else -1.0) * 0.65 + sin(phase) * 0.35
			"saw": wave = (fmod(phase / TAU, 1.0) * 2 - 1) * 0.6 + sin(phase) * 0.4
			"noise":
				filtered = lerpf(filtered, noise.randf_range(-1, 1), clampf(hz / rate, 0.02, 0.9))
				wave = filtered * 2.0
			"chime":
				var note := phase
				if event == "victory": note *= [1.0, 1.25, 1.5, 2.0][mini(3, int(t * 4))]
				wave = sin(note) * 0.65 + sin(note * 2.01) * 0.23 + sin(note * 3.98) * 0.12
			_: wave = sin(phase)
		var envelope := minf(seconds / float(preset.attack), 1.0) * pow(1.0 - t, float(preset.decay))
		var sample := clampi(int(wave * envelope * float(preset.volume) * 32767), -32767, 32767)
		bytes.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	cache[event] = stream
	return stream

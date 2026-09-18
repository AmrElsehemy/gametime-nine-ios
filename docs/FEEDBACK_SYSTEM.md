# Nine Feedback System

Nine uses a small semantic feedback layer so gameplay intent, not framework calls, defines the sensory response.

## Semantic events

- `placement`
- `removal`
- `invalid`
- `hint`
- `undo`
- `reset`
- `solved`
- `milestone`

Each event maps to a haptic intensity/sharpness and a short procedural tone. The current tones are generated at runtime with `AVAudioEngine`; there is no external sound-asset dependency on the v1 critical path. If mastered samples later prove materially better, the semantic API can stay unchanged.

## Haptics

Core Haptics is preferred when supported. If the engine is unavailable or throws, the game falls back to UIKit feedback generators. Failure is intentionally swallowed at this boundary so sensory feedback can never block gameplay.

Invalid feedback is sharper/stronger than a normal placement. Solve/milestone feedback is celebratory rather than punitive.

## Audio

Audio uses an ambient, mix-with-others session and a pre-attached `AVAudioPlayerNode` for low-latency cues. Tone generation is intentionally short and restrained so repeated placement does not become fatiguing.

## Player control

Sound and haptics persist independently through `NineFeedbackPreferenceStore`. The current gameplay shell exposes direct toggles; issue #15 can move these controls into the final settings surface without changing the preference contract.

## Motion

- valid placement: quick scale/fade settle
- invalid placement: short horizontal shake plus existing non-color conflict ring
- solve: board wave + completion card
- tutorial guidance: pulsing target ring

When iOS Reduce Motion is enabled, repeated/pulsing and shake/scale choreography is suppressed. The static conflict ring, guidance text and completion state remain visible, so meaning does not depend on motion.

## Reuse policy

This system remains local to Nine for now. GameTimeKit should absorb a shared semantic feedback abstraction only after Game #002 proves that the event vocabulary/engine boundary is genuinely reusable.

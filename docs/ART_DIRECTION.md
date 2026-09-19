# Game #001 — Visual Identity

Status: **Direction selected for prototype**  
Internal codename: **Nine**  
Public name: **not locked**

## Creative objective

Game #001 must look like an ownable Knowlly Games product, not a Queens/chess clone and not an engineering prototype.

The visual system must remain readable from 6×6 through 9×9 boards, survive small iPhone screens, capture well in vertical video, and be producible mostly with native vector/procedural rendering so iteration stays fast.

## Directions considered

### A. Tactile Territories — SELECTED

A warm, dimensional puzzle board made of softly raised irregular territories. The player places a small crafted **token** that feels halfway between a polished game piece, pebble and collectible object.

Characteristics:
- soft off-white / warm-neutral canvas
- irregular colored territory fills with restrained saturation
- shallow elevation and soft shadow rather than heavy 3D
- one distinctive abstract token, not a crown/queen/chess piece
- crisp micro-motion on placement
- conflicts expressed with shape/ring/pulse as well as color
- completion transforms the board into a calm kinetic celebration

Why selected:
- immediately readable
- distinctive without requiring huge asset production
- easy to render procedurally with SpriteKit/Core Graphics
- scales cleanly to dense boards
- attractive in App Store screenshots and short-form video
- supports future themes/cosmetics without changing the mechanic

### B. Luminous Glass

Dark background, translucent colored regions, luminous glass markers and light trails.

Strengths: premium, dramatic, excellent motion.  
Risk: lower daylight readability, easier to become visually noisy, less forgiving for accessibility.

### C. Paper Cut Logic

Layered paper/cardboard territories with stamped tokens and playful cut-paper motion.

Strengths: friendly and tactile.  
Risk: can skew too juvenile/craft-like and makes dense 9×9 boards visually busy.

## Selected visual language — Tactile Territories

### Canvas
- warm neutral background rather than pure white
- no visible chessboard checker pattern
- generous breathing room around the board
- shell UI visually secondary to the puzzle

### Territories
- regions are the main color carrier
- neighboring regions must differ in hue/value sufficiently to read instantly
- subtle inset/raised treatment creates depth without thick borders
- territory boundaries use shape + spacing, not only color
- palette is deliberately soft enough that markers/conflict states dominate attention

Initial palette family for prototyping:
- Coral: `#F58E7E`
- Apricot: `#F3B46D`
- Butter: `#EBCF72`
- Sage: `#8DC7A5`
- Aqua: `#78C6C8`
- Sky: `#7EA9E1`
- Lavender: `#A58AD8`
- Rose: `#D98EBC`
- Neutral canvas: `#F5F2EA`
- Ink: `#262624`

These are prototype values, not a locked brand palette. Accessibility testing can shift them.

### Marker / token

Working object: **the Pebble**.

It is an abstract, vertically oriented polished token with:
- rounded/faceted silhouette
- tiny central notch or inset mark
- soft highlight and contact shadow
- strong monochrome silhouette at small sizes

It must never read as a chess queen/crown.

Possible later theme variants can change material while preserving silhouette: ceramic, glass, stone, chrome, candy, neon.

### Board states

#### Empty
Calm territory surface.

#### Valid placement
- token lands with short scale/settle motion
- subtle shadow compression
- soft tactile click

#### Conflict
- affected token gets a thin interrupted ring or split halo
- conflicting row/column/region receives a short boundary pulse
- color shifts toward warning but shape/ring carries meaning too
- no permanent angry-red board

#### Hint
- target cell breathes once or twice
- optional faint contour/ghost token
- never auto-place unless the player confirms

#### Selected / focus
Use outline/elevation rather than changing region identity.

#### Completion
Sequence should feel materially larger than a normal move:
1. final token settles
2. board briefly becomes still
3. regions lift/pulse in a travelling wave
4. tokens emit a subtle highlight sweep
5. restrained particles/rings move outward
6. result/next action arrives after the visual payoff

Target: satisfying in a 2–3 second screen recording without becoming casino-like.

## Typography and shell UI

Use Apple system typography initially.
- Prefer SF Rounded where it improves friendliness.
- Strong numeric/time legibility.
- Avoid a custom font dependency for v1 unless the public brand later demands it.

Buttons are compact, rounded and visually quiet. Gameplay owns the screen.

## Motion principles

- short, physical and interruptible
- normal placement roughly 120–220 ms
- conflict feedback shorter than celebration
- completion can use 600–1400 ms of staged motion
- avoid constant floating/bouncing
- Reduce Motion substitutes opacity/highlight changes for large movement

## Sound and haptic tone

Sound reference family:
- placement: small ceramic/wooden click
- invalid/conflict: muted double tick, never harsh buzzer
- hint: soft high-frequency sparkle/tone
- solve: short layered chime with one warm low note + brighter resolution

Haptics:
- placement: light crisp transient
- invalid: soft warning pattern
- solve: staged success pattern aligned with the completion wave

## App icon direction

The icon must not depend on the public title being “Nine.”

Initial concept:
- warm neutral or saturated single-field background
- 3–5 abstract colored territory shapes meeting near center
- one oversized Pebble token in front
- no text
- no literal chess crown
- no tiny full puzzle board

The silhouette should remain recognizable at Home Screen size and in App Store search results.

## Accessibility rules

- color is never the only representation of conflict or selection
- maintain usable contrast between region, boundary, marker and shell
- hit targets remain generous even when visual cells are small
- Reduce Motion has a calmer equivalent
- haptics/audio can be disabled independently

## Public-name gate

Do **not** decide the public App Store name from text alone.

Lock the public name only after:
1. a polished board prototype exists
2. an app-icon prototype exists
3. a 10-second gameplay capture exists
4. candidate name looks credible beside the actual product

The repository remains `gametime-nine-ios` regardless of the public name.

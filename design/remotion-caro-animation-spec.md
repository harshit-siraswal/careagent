# Caro Mascot Remotion Animation Spec

Use this if the team builds the mascot animation in Remotion.

## Goal

Caro should feel like a friendly healthcare robot companion with the polish of a native Apple health app. Use the supplied robot reference as inspiration: white rounded shell, dark visor, cyan eyes, antenna, and stethoscope detail. Keep it softer and less toy-like than a children's mascot.

## Mascot Shape

- Rounded white robot head/body.
- Dark glossy visor.
- Cyan glowing eyes and small smile dots.
- Small antenna pulse light.
- Optional stethoscope and heart/pulse badge.
- Compact silhouette that still reads clearly at 48 to 72 px.

## Animation States

Idle:

- 3.2 second loop.
- Body floats 4 to 6 px upward and settles.
- Antenna glow pulses softly.
- Blink every 4 to 5 seconds.
- Cyan chest/visor glow breathes subtly.

Listening:

- Body leans 2 degrees toward message bubble.
- Pulse ring tightens to a smaller radius.
- Eyes blink once.

Medicine reminder:

- Chest badge bounces once.
- Yellow reminder dot appears for 500 ms.
- Body scales 1.03 then settles.

Urgent:

- Ambient glow shifts from cyan to soft red.
- Pulse ring accelerates to a 1.2 second loop.
- No flashing faster than accessibility limits.

## Remotion Implementation Notes

- Use `design/assets/caro-mascot.svg` as the base art, or recreate it as layered SVG shapes in React.
- Use `useCurrentFrame`, `useVideoConfig`, `interpolate`, and `spring`.
- Keep the animation under 150 lines for the mascot component.
- Expose props: `state`, `size`, `reducedMotion`.
- Render still frames at idle, listening, reminder, and urgent states for design review.

## Safety and Accessibility

- Respect reduced motion.
- Do not flash.
- Keep urgent animation clear but calm.
- Animation should never block emergency action controls.

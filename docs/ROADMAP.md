# Roadmap (planned, details to follow from the user)

1. **Low-battery notice** — the user sets a threshold; at or below it the notch shows a HUD capsule like the volume / brightness
   one (replacing the compact capsule with the same tuck-in animation). Needs: battery level source (IOKit power sources, no
   permission), threshold setting (slider + number field), show once per crossing (not on every poll), charging state.
2. **Single-module big capsule** — inspired by showing one module alone while testing. For modules such as reminders, calendar
   and notes: hovering a module's title shows a muted (`text-muted`) arrow; clicking the title or the arrow glides to that module's
   own big capsule, a larger interface for it (or its extension, e.g. music shows the playlist). Needs: per-module "detail"
   view, the transition (shared-element morph of the capsule width / height), a way back, hover affordance on titles.

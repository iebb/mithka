# Generated message bubble assets

These twelve presets were generated with GPT-image-2 on 2026-07-25 and replace
the two earlier screenshot-derived examples. No pixels from either reference
screenshot are present in the generated assets.

## Shared generation contract

- One empty, front-facing horizontal chat frame on a solid `#00ff00`
  background.
- A uniform center and repeatable middle edge spans for nine-slice rendering.
- Decoration confined to the four corner zones.
- No text, logos, watermarks, recognizable characters, branded motifs, or
  copyrighted designs. Character-led genres use newly invented fictional
  figures confined to the corner zones.
- Explicitly excluded folded paper, tape, dangling charms, crowns, cats, and
  designs resembling the supplied screenshots.

## Directions

| Asset | GPT-image-2 direction |
| --- | --- |
| `midnight-aurora.png` | Deep indigo frame with cyan and magenta light facets. |
| `solar-porcelain.png` | Warm ivory porcelain with coral, navy, and apricot inlays. |
| `berry-orbit.png` | Dusty rose editorial frame with plum orbital geometry. |
| `arctic-blueprint.png` | Ice-blue technical frame with cobalt drafting marks. |
| `ember-arcade.png` | Graphite frame with amber edging and original circuit traces. |
| `lilac-constellation.png` | Lavender frame with abstract glints and constellation lines. |
| `forest-familiar.png` | Storybook forest frame with an original moss familiar. |
| `ink-wanderer.png` | Ink-wash frame with an original wandering cloud spirit. |
| `pixel-cadet.png` | Crisp pixel-art frame with an original robot cadet. |
| `cosmic-mechanic.png` | Retro sci-fi frame with an original alien mechanic. |
| `pastry-pal.png` | Flat gouache patisserie frame with an original pastry sprite. |
| `noir-detective.png` | Hand-inked comic frame with an original moth detective. |

## Export process

The generated green backgrounds were removed with a chroma-key helper. The
full-resolution generation inputs are intentionally not stored in this
repository; the compact runtime exports under `assets/message_bubbles/` are
canonical.

To regenerate the compact exports, place the twelve transparent source PNGs in
an external directory and pass that directory to
`scripts/compact_generated_message_bubbles.dart`. The script keeps only the
corner and edge regions around a one-pixel logical center slice. Final exports
are 49×37 logical pixels, with 98×74 two-times variants, so every compact source
fits inside a 100×100 canvas.

```bash
dart run scripts/compact_generated_message_bubbles.dart /path/to/sources
```

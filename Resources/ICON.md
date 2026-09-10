# DuoLid icon

The owner supplied the laptop artwork. OpenAI Image Generation edited its display to show a bottom-anchored folding desktop, black space above it, a blurred window, and soft violet/cyan/peach edge bleed. The laptop pose, keyboard, materials, and colors remain the visual basis.

`IconArtwork.png` is the approved generated master. `scripts/make-icon.swift` performs the macOS export with transparent padding and a rounded tile mask. It produces ten representations (16–1024 pixels) and `DuoLid.png`. `iconutil` assembles `DuoLid.icns`.

Final artwork prompt, abbreviated only to remove local reference paths:

> Edit only the laptop display in the original artwork. Keep the pose, tile, materials, keyboard, reflections, and colors. Show the actual DuoLid folding effect: a desktop plane anchored at the bottom, with its upper edge descending into the lower portion of the display and black space above. Use the production-rendered closing frame as a geometry reference. Include softly blurred desktop content and broad, diffuse pastel bleed following the projected edge. No new logos, watermarks, or text.

Tool: `image_gen.imagegen`, with the owner-provided artwork and a synthetic frame from the production renderer as references. A later transparency-only generation produced a visible checkerboard and was rejected; it is not bundled. The approved artwork is exported with real alpha by the icon packaging script.

# App icon

The original artwork is `assets/app-icon.png`, generated with the built-in image-generation tool. `scripts/build-icon.sh` packages it into a native `.icns` with standard and Retina sizes from 16 to 1024 pixels. Every app build includes this icon through `CFBundleIconFile`.

Generation prompt:

Use case: logo-brand. Asset type: a polished macOS application icon for Hand Mouse, a local camera hand-tracking mouse utility. Create one square 1024x1024 icon. A deep midnight-navy rounded-square macOS tile with a beautifully sculpted, simple ivory-white hand in the center: index finger extended upward, thumb visible, the other three fingers naturally curled. A small vivid mint-turquoise mouse cursor arrow beside the index fingertip visually connects pointing a finger to controlling a cursor. Bold readable silhouette, elegant soft 3D depth, subtle satin materials and restrained mint rim lighting, premium native desktop utility feel. The hand and cursor should remain clear at small Dock sizes. Straight-on view, balanced centered composition, generous internal margins. The rounded tile occupies about 88 percent of the canvas width. True transparent background outside the rounded tile, clean alpha edges. No text, no letters, no photo, no face, no extra objects, no tiny hand-landmark lines, no border around the canvas, no watermark.

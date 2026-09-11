# README media

- `icon.png`: the app's approved icon export, from owner-supplied artwork edited through OpenAI Image Generation.
- `fold.png`, `neutral-fold.png`, and `duolid-demo.mp4`: synthetic `PreviewDesktop` content processed through the application's actual `MetalRenderer`, exported offscreen. No user's screen is captured. The precomputed video illustrates appearance, not live frame pacing or measured performance.
- `workspace.png`: native DuoLid controls with a synthetic preview, made for documentation. No external app content.

Regenerate frames with `DuoLid --export-demo`, then encode at 60 fps with FFmpeg. Keep large frame sequences under ignored `artifacts/demo/`, not in Git.

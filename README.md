# Space Dots

I'm a huge fan of *Project Hail Mary*, and seeing it in IMAX was an incredible experience. When I saw Grace surrounded by Astrophage in “The Moment” scene, I knew I wanted to recreate that feeling for Apple Vision Pro.

Together with Charlene van Lieshout, I created Project Space Dots: our own unofficial Astrophage experience for Apple Vision Pro. It's a small side project made to share that experience with everyone, combining "The Moment" scene with a mixed-reality Astrophage so you can relive Grace's encounter in your own surroundings. There are also a few other gimmicks to discover!

## Technical details

- **Spatial particle system:** Four RealityKit emitters combine distant particles, two moving clusters and larger foreground bokeh. Their configured emission rates and lifetimes correspond to approximately 24,800 particles at full, steady-state emission; the actual number varies during startup, fades and recentering.
- **Organic movement:** The clusters drift and change shape independently, while particle size, colour, rotation and noise vary to give the swarm depth and motion.
- **Head-aware placement:** ARKit world tracking uses the headset's position and orientation to place the screen in front of the viewer. The screen stays anchored in the room, and the particle effect can be reoriented toward it from the viewer's current position.
- **Film synchronisation:** The effect starts around 16.8 seconds into the streamed clip and responds to playback state, seeking and the end of the video.
- **Interactive 3D models:** The floating models can be grabbed, moved and released. Their motion and collisions use custom physics with mesh-derived convex collision shapes.
- **Native visionOS experience:** Built with SwiftUI, RealityKit, ARKit and Metal in a mixed immersive space, keeping the viewer's surroundings visible.

## Requirements

- macOS with Xcode 26 or later and the visionOS SDK
- Apple Vision Pro or the visionOS simulator
- An internet connection for the embedded YouTube video

## Build and run

1. Open `Space Dots.xcodeproj` in Xcode.
2. Select the **Space Dots** target and open **Signing & Capabilities**.
3. Keep **Automatically manage signing** enabled and select your own Apple Developer team. No team is configured in this copy.
4. Select Apple Vision Pro or an Apple Vision Pro simulator and run the **Space Dots** scheme.

For a physical device, connect it to Xcode and enable Developer Mode if prompted. If Xcode reports that the bundle identifier is already in use, change `com.spacedots.app` to a unique identifier under **Signing & Capabilities**. The simulator can also be built without a development team.

The film is streamed from YouTube; playback depends on internet access and the video's availability for embedding. The app does not include a music player.

## Project structure

- `Space Dots/` — SwiftUI, RealityKit and Metal app code, assets and collider data.
- `Packages/RealityKitContent/` — local Reality Composer Pro content package.
- `Tests/` — standalone physics and collider checks.
- `Tools/` — tools for regenerating collider data after replacing a 3D model.

The collider tools require separate Python dependencies (`numpy`, `trimesh`, `scipy` and `coacd==1.0.9`); they are not needed to build or run the app.

## Special Thanks

**Charlene van Lieshout** — UX design and collaboration on the app experience

## Rights and attribution

Unofficial fan project by Kevin Otten. Not affiliated with or endorsed by Amazon MGM Studios, MGM or Prime Video. *Project Hail Mary* and related marks belong to their respective owners.

The film clip featured in Project Space Dots was uploaded to YouTube by Prime Video. The app streams the clip directly from YouTube; I built the mixed-reality experience around it.

The Rocky's Grace models were supplied by their creators as 3D-print files. The Petrova Indicator is an original model inspired by the film. The film is streamed from YouTube and is not bundled with the app. Verify permission to redistribute the bundled models, images and other third-party assets before publishing this repository or distributing a build.


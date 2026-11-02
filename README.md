# Space Dots

I'm a huge fan of *Project Hail Mary*, and seeing it in IMAX was an incredible experience. The moment I saw the Astrophage, I knew I wanted to recreate that feeling for Apple Vision Pro.

Together with Charlene van Lieshout, I created Space Dots: our own unofficial Astrophage experience for Apple Vision Pro. It's a small side project made to share that experience with everyone, combining a film clip with a mixed-reality Astrophage effect so you can relive Grace's encounter in your own surroundings.

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

- **Charlene van Lieshout** — UX design and collaboration on the app experience

## Rights and attribution

Unofficial fan project by Kevin Otten. Not affiliated with or endorsed by Amazon MGM Studios, MGM or Prime Video. *Project Hail Mary* and related marks belong to their respective owners.

The Rocky's Grace models were supplied by their creators as 3D-print files. The Petrova Indicator is an original model inspired by the film. The film is streamed from YouTube and is not bundled with the app. Verify permission to redistribute the bundled models, images and other third-party assets before publishing this repository or distributing a build.

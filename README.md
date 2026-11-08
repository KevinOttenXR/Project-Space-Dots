<div align="center">

# SPACE DOTS

Step into a mixed-reality interpretation of **“The Moment”**, where thousands of Astrophage particles come to life and fill your space.

*A personal Apple Vision Pro project by Kevin Otten and Charlene van Lieshout.*

`Apple Vision Pro` · `visionOS` · `SwiftUI` · `RealityKit` · `ARKit` · `Metal`

---

### HERO IMAGE / GIF PLACEHOLDER

[About](#about-the-project) · [Showcase](#experience-showcase) · [Features](#features) · [Technology](#behind-the-experience) · [Build](#build-and-run) · [Film & Credits](#inspiration-assets--credits)

</div>

## About the project

I'm a huge fan of *Project Hail Mary*, and seeing it in IMAX was an incredible experience. When I saw Grace surrounded by Astrophage in “The Moment” scene, I knew I wanted to recreate that feeling for Apple Vision Pro.

Together with **Charlene van Lieshout**, we created **Space Dots**. This personal side project combines the film scene with mixed-reality particles so you can relive Grace's encounter in your own surroundings.

Instead of simply watching the scene, you can experience the Astrophage phenomenon in your own space.

## Experience showcase

| The Moment | Spatial cinema | Rocky's models |
| :---: | :---: | :---: |
| **VIDEO 01 PLACEHOLDER** | **VIDEO 02 PLACEHOLDER** | **VIDEO 03 PLACEHOLDER** |
| Astrophage fills your surroundings as the scene unfolds. | Move and resize the floating cinema screen with hand gestures. | Interact with Rocky models on the home screen. |

## Features

### Astrophage particle system

Four RealityKit emitters combine distant particles, two independently moving clusters, and larger foreground bokeh. Particle size, colour, rotation, and noise vary to give the effect depth and motion.

| Particle system | Configuration |
| --- | --- |
| Estimated full steady-state emission | **≈ 24,800 particles** |
| RealityKit emitters | **4** |
| Independently moving clusters | **2** |

*The particle estimate comes from configured emission rates and lifetimes. Actual counts vary during startup, fades, and recentering.*

### Organic movement

The clusters drift and change shape independently. Variation in each particle's appearance helps create a cloud that feels continuous rather than static.

<p align="center">
  <img src="Explainer%20content/Astropaghe_ZoomedOut.gif" alt="Space Dots - Vision Pro Simulator" width="720">
</p>

### Interactive Rocky models

Find Rocky models on the home screen and interact with them as part of the spatial experience. The move like they are in zero gravity. You can trow them away, but don't worry! They will come back to you. 

**VIDEO PLACEHOLDER**

## Panel controls

- **Move the panel:** Look at it, pinch and hold, and move your hand. Push or pull to adjust distance.
- **Resize the panel:** Pinch with both hands and move them apart to enlarge it, or closer together to make it smaller.

**VIDEO PLACEHOLDER**

## Requirements

- A Mac with Xcode 26 or later and the visionOS SDK.
- Apple Vision Pro or the visionOS simulator.
- Internet access for the embedded YouTube clip.

Some spatial behaviour requires a physical Apple Vision Pro to evaluate fully.

## Build and run

1. Clone or download this repository.
2. Open `Space Dots.xcodeproj` in Xcode.
3. Select the **Space Dots** target and open **Signing & Capabilities**.
4. Keep **Automatically manage signing** enabled and select your Apple Developer team. No team is configured in the repository.
5. Select Apple Vision Pro or an Apple Vision Pro simulator and run the **Space Dots** scheme.

Playback requires internet access and depends on YouTube allowing the video to play in the app. Space Dots does not include a music player.

## Inspiration, Assets & Credits

Space Dots is an independent fan project inspired by *Project Hail Mary* (2026), based on the novel by Andy Weir.

This section brings together the original film, the book, the assets used in the experience, and the people behind the project.

### Original Film & Video

The Astrophage experience is inspired by **“Having A Moment”**, the scene in which Ryland Grace encounters Astrophage.

Space Dots streams the original video published by Prime Video on YouTube. The video is not included in the app or repository.

**[Watch “Having A Moment” on YouTube](https://www.youtube.com/watch?v=vppn4gX0eUI)**

**Watch the film**

- [Prime Video](https://www.primevideo.com/detail/0J0SQMKFG51K9S3UTU9SDEMT7D)
- [Apple TV](https://tv.apple.com/nl/movie/project-hail-mary/umc.cmc.7jxdlxvz304lj3iwhtrhbe8fv)

**Read the original book**

- [Project Hail Mary by Andy Weir](https://www.amazon.com/dp/0593135229)

### 3D Models & Assets

Space Dots combines third-party 3D models adapted for Apple Vision Pro with custom-made assets and particle effects.

| Asset | Source / Credit |
| --- | --- |
| Rocky's 3D models | [Project Hail Mary – Amazon](https://www.amazon.com/salp/projecthailmary?hhf) |
| Petrova Indicator | Original 3D model by Kevin Otten |
| Astrophage particle system | Custom RealityKit implementation by Kevin Otten |

*Third-party assets remain the property of their respective creators and are subject to their original license terms.*

<h2>Project Creators</h2>

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>Kevin Otten</h3>
      <strong>Development & Technical Implementation</strong>
      <p>3D implementation, particle systems, RealityKit development and technical integration.</p>
    </td>
    <td width="50%" valign="top">
      <h3>Charlene van Lieshout</h3>
      <strong>UX Design & Experience</strong>
      <p>User experience design, interaction concepts and collaboration on the app experience.</p>
    </td>
  </tr>
</table>

### Rights & Disclaimer

**Copyright © 2026 Kevin Otten. All rights reserved.**

The original Space Dots source code is publicly viewable. Copying, modifying or redistributing it requires prior permission, except where applicable law or separately licensed third-party components allow otherwise.

Space Dots is an independent, unofficial fan project. It is not affiliated with, sponsored by or endorsed by Amazon MGM Studios, MGM or Prime Video.

*Project Hail Mary*, its characters, film footage and associated intellectual property belong to their respective rights holders.

The original film clip is streamed from YouTube and is not redistributed with the app. Third-party 3D models remain subject to their creators' rights and applicable licenses.

---

<div align="center">

*Made for Apple Vision Pro · Inspired by Project Hail Mary*

</div>

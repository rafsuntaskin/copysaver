# CopySaver Layered C icon

Selected by the user on November 12, 2026. This icon selection is independent of the unselected UI concept 3.

- `layered-c-master.png`: original built-in imagegen output, with transparent margins.
- `../../App/Resources/AppIcon.icns`: native 16–1024 pixel representations generated with Apple sips/iconutil; both packaging paths copy this resource.
- The sidebar uses the same bundled icon. Menu bar and navigation controls retain semantic template symbols.

Generation prompt: CopySaver macOS icon, a frontal graphite rounded-square tile with two broad nested rounded C shapes, cobalt outer and pale silver inner, offset like copied sheets. Matte ceramic/anodized-metal surfaces, restrained shallow bevels, strong negative space and a bold silhouette. Transparent outside the tile; no wordmark, locks, shields, glow or decorative circuitry. Generated with the built-in imagegen tool, then packaged without changing the selected artwork.

Regenerate the ICNS by making a standard `.iconset` with `icon_16x16.png` through `icon_512x512@2x.png`, resizing the master with `sips -z`, and using `iconutil -c icns`. This is asset packaging; it does not change app identity, signing, encryption or saved data.

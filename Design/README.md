# Icon sources

The icon is two lines of writing with a thread running through them, ending in a
loop — the throughline the app is for. Three colours, all from `Theme`:
`#FAF7F2` paper, `#2B2622` ink, `#B5703C` accent.

- `icon-mac.svg` — rounded rect baked in, artwork inset to Apple's 824/1024
  content area, transparent outside so the Dock silhouette is right
- `icon-ios.svg` — full bleed; the system applies the mask
- `icon-ios-dark.svg` — inverted paper, same accent

Weights are deliberately heavier than they look right at 1024. An icon is
designed for 32px and merely inspected at full size.

## Regenerating the asset catalogue

```bash
./Design/render-icons.sh
```

# CopySaver design baseline

Source: approved concepts 1 and 2 in designs/README.md and spec sections 4 and 9. This is a native SwiftUI/AppKit product, not a web interface.

## Scene and theme

Someone moving between work apps in a bright office uses a readable light library; the same person retrieving text in a dim evening workspace needs a quiet dark Focus panel. Follow the system appearance for both surfaces by default and offer explicit overrides. The mockups show equivalent structures in different appearances, not forced per-surface themes.

## Color and material

Restrained color strategy. Use semantic macOS window, content, separator, label, secondary-label, and accent colors so native appearance and contrast settings work. The user's selected system accent carries selection and primary actions. Favor opaque surfaces, thin separators, and standard window/panel shadows. No decorative gradients, side stripes, or glass layers. Native semantic colors take precedence over inventing a separate fixed web palette.

## Typography

System font and SF Symbols. App title approximately 17 pt semibold; section title 18–20 pt; row/body 13–14 pt; metadata 11–12 pt. Text details may use the system monospaced font where preserving code/address formatting helps. Keep labels readable and support native accessibility scaling where applicable. No display font or rasterized UI text.

## Full window, concept 1

Three columns: approximately 210 pt navigation sidebar, 300–360 pt item list, and flexible text detail/editor. Start near 1040×680 pt and remain useful at smaller desktop widths through resizing and pane adaptation. Keep native traffic lights, search above the list, subdued source/time metadata, selected-row fill, and copy/save actions near the detail footer. History and Snippets use the same shell. Pinned is a history filter.

Keep the list title on its own line, followed by a full-width rounded native search field with explicit focus and Clear search. A small Recent/Results label and result count establish list context. Result rows use 32 pt symbol containers, 13 pt titles and 11 pt metadata, with approximately 62 pt library / 50 pt Focus row heights. Reuse the navigation hover/press/focus vocabulary; selection never scales or slides. Preview source context sits above the text, Pin/Edit and More actions sit in the header, and Copy stays at the lower trailing edge. Text views have transparent native backgrounds and reset their private editing state when the selected record changes.

## Focus mode, concept 2

A compact floating panel with search first, History/Snippets switch, optional pinned section, recent items, and a slim keyboard/action footer. No full sidebar or large preview pane. Focus search on opening; arrows navigate; Return copies and dismisses; Escape dismisses; Open Library transfers the current view/selection. Global shortcut configuration and full-screen/Space behavior require native integration validation.

Use the shared search field at a larger type size, compact single-line result titles, and understated keyboard hints. Distinguish Copy (Command-C, stays open) from Copy & close (Return); Library carries the current query and selection. Result transitions stay immediate, with short background-only hover/press fades and no delayed search or animated list reordering.

## State and content rules

- Locked surfaces show no item names, counts, content, or previous queries.
- Empty states offer a useful action and do not seed a real vault with examples.
- A deliberate developer UI-preview mode may show synthetic records, with an unmistakable sample-data label and no clipboard/Keychain/vault access. It must never unlock a real vault or be a fallback for failed authentication.
- Sensitive bodies remain masked in previews and accessibility output. Community reveal/edit/copy requires no additional authentication; the protected profile retains its original authentication. Explicit reveal expires on deactivation or after 30 seconds.
- Sidebar rows own their entire hit area. Only the active destination uses an accent selection fill; hover and press use quiet neutral fills. Keep text/icon positions stable, use a distinct keyboard focus outline, and fade state changes without scaling or sliding. Respect Reduce Motion and increased contrast.
- Show copy/save success only after the real operation succeeds. Controls for unavailable functionality must not pretend to work.
- Preserve dirty-draft warnings for normal navigation; lock clears drafts without waiting for confirmation.

## Craft and verification

Use live SwiftUI text, controls, lists, and SF Symbols for the approved visual ingredients; the mock PNGs are references only. No additional raster assets are needed for this utility. Use short state transitions, respect reduced motion, and inspect the running native app at normal and compact sizes in light/dark appearance. Record pending checks rather than treating compilation or a generated screenshot as UX, accessibility, or security validation.

## Launcher widget

The approved generic launcher requirement is carried into native WidgetKit: small uses name/icon, a quiet Clipboard & snippets label, and Open Focus Mode; medium adds separate History/Snippets links. Use system widget margins, semantic foregrounds and SF Symbols. This is the same restrained utility direction, with no content thumbnails, status metrics, new imagery, or alternate visual theme. Actual system gallery rendering remains a native validation gate.

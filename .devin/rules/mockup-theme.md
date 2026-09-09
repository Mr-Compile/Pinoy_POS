# Pinoy POS Mockup Theme

Use this guide when creating or editing HTML mockups in `mockups/`. All mockups should share the same visual system so the product feels like one app.

## Purpose

HTML mockups are visual references for Flutter screens. They must match:

- the live Flutter theme (`lib/core/app_theme.dart`)
- the existing component vocabulary (cards, chips, pills, icon badges, bottom nav)
- the responsive phone-frame presentation used across the project

## File locations

- Mockups live in `mockups/`
- Current mockups:
  - `index.html` — Products & Categories
  - `sales.html` — Sales list
  - `pos.html` — POS / cart
  - `dashboard.html` — Dashboard
  - `login.html` — Login form

## Theme tokens

Each mockup defines these CSS custom properties on `:root`:

### Dark (`data-theme="dark"`)

```css
--bg: #070D19;
--surface: #121C31;
--surface-elev: #152348;
--border: #263A63;
--divider: #1A2445;
--text: #F1F4F7;
--text-2: #B8C5E0;
--text-3: #8C9AB8;
--primary: #4B82E9;
--primary-strong: #2C68D7;
--page-bg: #0B1220;
--appbar: #1B4CAF;
```

### Light (`data-theme="light"`)

```css
--bg: #F5F8FC;
--surface: #FFFFFF;
--surface-elev: #EEF4FF;
--border: #D7E0EE;
--divider: #E7ECF4;
--text: #172033;
--text-2: #52627A;
--text-3: #8A9AB3;
--primary: #2563C7;
--primary-strong: #1B4CAF;
--page-bg: #E8EDF5;
--appbar: #2563C7;
```

### Shared semantic colors

```css
--success: #16A34A;
--warning: #D97706;
--error: #DC2626;
--info: #4B82E9;
--purple: #8B5CF6;
--pink: #EC4899;
--teal: #06B6D4;
--amber: #F59E0B;
--radius-card: 18px;
--radius-icon: 11px;
```

## Phone frame

Use the same phone frame for every mobile mockup:

```css
.phone {
  width: 380px;
  background: var(--bg);
  border-radius: 36px;
  border: 1px solid var(--border);
  overflow: hidden;
  box-shadow: 0 24px 64px rgba(0,0,0,.35);
}
```

Inside the phone:

1. **Status bar** — 30px, left clock, right wifi + battery icons
2. **App bar** — solid `var(--appbar)`, 20px bold white title, optional back arrow, theme/notification/avatar actions
3. **Screen** — padded content area
4. **Bottom nav** — only for shell screens; pushed screens omit it

## App bar

The `AppHeader` is a solid brand bar:

- Background: `var(--appbar)`
- Title: 20px, bold, white
- Action icons: white, 19px
- Avatar: 32px circle, white border, white initials
- Back button (for pushed screens): 21px white chevron

## Cards

Use the same card style for summary, list, and form cards:

```css
background: var(--surface);
border: 1px solid var(--border);
border-radius: var(--radius-card);
padding: 14px;
```

## Status / icon badges

Semantic icon badges use a 16% tinted background and the matching color for the icon:

```css
.c-green   { background: rgba(22,163,74,.16);  color: var(--success); }
.c-amber   { background: rgba(217,119,6,.16);  color: var(--warning); }
.c-red     { background: rgba(220,38,38,.16);  color: var(--error); }
.c-blue    { background: rgba(75,130,233,.16); color: var(--info); }
.c-purple  { background: rgba(139,92,246,.16); color: var(--purple); }
```

Badges may be circles (34px) or rounded squares (38px with 11px radius).

## Pills

Pills use the same 16% tint with matching text:

```css
.pill {
  font-size: 10.5px;
  font-weight: 700;
  padding: 4px 10px;
  border-radius: 20px;
}
```

Use solid variants for high-priority states (e.g. `pill-solid-green` for confirmed).

## Chips

Filter/choice chips:

```css
background: var(--surface);
border: 1px solid var(--border);
color: var(--text-2);
padding: 7px 14px;
border-radius: 20px;
```

Selected state:

```css
background: var(--primary);
border-color: var(--primary);
color: #fff;
```

## Typography

- Page title (outside phone): 22px, bold, `var(--text)`
- Section label: 12.5px, bold, uppercase, `var(--text-2)`
- Card title: 14.5px, bold, `var(--text)`
- Body: 14px, medium, `var(--text)`
- Metadata / subtitle: 12px, `var(--text-3)`
- Stat value: 20px, extra bold, `var(--text)`
- Stat label: 10.5px, bold, uppercase, `var(--text-3)`

## Icons

- Define SVG `<symbol>`s in a hidden sprite block (`<svg width="0" height="0">`)
- Reference with `<svg><use href="#i-name"/></svg>`
- Reuse the same icon set across mockups
- Icon fill should use `var(--...)` or `currentColor`

## Theme toggle

Every mockup should let the user switch light/dark. Use this pattern:

```html
<button class="theme-toggle" onclick="toggleTheme()">…</button>
```

```js
function toggleTheme() {
  const root = document.documentElement;
  root.dataset.theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
}
```

Set `<html data-theme="dark">` as the default so the first view matches the mockup style.

## Adding a new mockup

1. Copy the closest existing mockup (`login.html` for forms, `sales.html` for lists, `pos.html` for POS flows, `dashboard.html` for dashboards).
2. Keep the CSS token block unchanged.
3. Keep the phone frame, status bar, and app-bar structure.
4. Add/replace screen content only.
5. Use the same spacing, card, chip, pill, and badge conventions.
6. Keep the page header + theme toggle outside the phone.
7. Open a browser preview for review.

## Consistency checks

Before finishing a mockup, verify:

- [ ] Light and dark themes both render correctly
- [ ] The phone frame matches the others
- [ ] The app bar matches `AppHeader` (solid brand, white title, white icons)
- [ ] Cards, chips, pills, and icon badges use the same styles
- [ ] Typography follows the hierarchy above
- [ ] No hardcoded hex colors outside the token block
- [ ] A theme toggle works on the page

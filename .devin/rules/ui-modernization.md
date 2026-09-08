---
description: "Global UI/UX modernization rules for Pinoy POS — applies to every screen, role, dialog, form, list, card, dashboard, POS flow, and payment screen"
trigger: always_on
---

# GLOBAL UI/UX RULE — PINOY POS

This is a GLOBAL RULE for the entire Pinoy POS application.

Apply these rules to EVERY screen, EVERY role, EVERY dialog, EVERY form, EVERY list, EVERY card, EVERY dashboard, EVERY POS flow, EVERY payment screen, EVERY sales screen, and EVERY future UI component.

Do not design screens independently.

The entire application must behave and look like ONE cohesive, modern, professional POS system.

IMPORTANT:
- Do NOT build, compile, package, or generate an APK.
- Do NOT run build commands as part of UI/UX QA.
- Only inspect, test, analyze, debug, and modify the source code.
- Do not change backend/business logic unless required to make an existing UI feature function correctly.
- Preserve existing functionality and data.
- Do not introduce fake/mock data just to make a UI look complete.

## 1. USER-FIRST DESIGN

Every screen must answer these questions:

1. What is the user trying to accomplish?
2. What information is most important?
3. What action should the user take next?
4. What information is secondary?
5. What can be removed or collapsed?

Never design a screen simply by placing all available data on it.

Prioritize usability over visual decoration.

## 2. INFORMATION HIERARCHY

Every screen MUST have a clear hierarchy:

LEVEL 1 — Primary
- page purpose
- most important information
- primary action
- critical status
- important totals

LEVEL 2 — Secondary
- supporting information
- filters
- metadata
- related information

LEVEL 3 — Tertiary
- timestamps
- IDs
- secondary descriptions
- less frequently used actions

Do not give every piece of information the same font size, weight, contrast, or visual emphasis.

The user's eye should immediately know what matters.

## 3. PRIMARY ACTION RULE

Every functional screen should have a clearly identifiable primary action.

Examples:

- POS: Checkout / Pay
- Products: Add Product
- Categories: Add Category
- Sales: View Transaction
- Settings: Save
- Trash: Restore / Permanently Delete

The primary action must visually stand out without overwhelming the interface.

Secondary and destructive actions must have lower visual priority unless they are the current task.

## 4. Z-PATTERN / F-PATTERN

Use natural reading patterns.

For mobile: use a clear vertical/F-pattern or Z-pattern flow.

Recommended general flow:

Header
↓
Context / summary
↓
Search / filter
↓
Primary content
↓
Supporting content
↓
Primary action

Do not randomly distribute important information around the screen.

The user's eye should naturally move toward the next required action.

## 5. RESPONSIVE DESIGN IS REQUIRED

Never force one layout onto every device.

The UI must adapt based on AVAILABLE WIDTH.

PHONE PORTRAIT:
- mobile-first layout
- single-column or carefully designed compact layout
- vertically stack related sections
- prioritize the most important content
- avoid horizontal overflow

TABLET:
- adaptive multi-column layout
- use available space efficiently
- split related content when useful

DESKTOP:
- expanded multi-column layout
- larger information density where appropriate

Do not simply shrink the desktop UI to fit a phone.

Content presentation may change between breakpoints while preserving the same information and functionality.

## 6. RESPONSIVE CONTENT TRANSFORMATION

When a desktop/tablet component cannot work well on a phone, transform its presentation.

Example — Desktop:

Receipt | Customer | Date | Payment | Total | Status

Mobile:

Receipt
Customer
Date
Payment       Total
Status

Do not create horizontal scrolling just to preserve a desktop table.

Use cards, stacked sections, expandable details, or other mobile-appropriate representations.

## 7. POS MOBILE-FIRST RULE

POS is a high-frequency workflow.

On portrait phones, prioritize:

Search
↓
Categories
↓
Products
↓
Cart
↓
Total
↓
Checkout

Do not force a desktop Products | Cart layout onto a narrow phone.

On tablet/desktop, use Products | Cart when the available width supports it.

The cashier should be able to complete a sale with minimal unnecessary navigation.

## 8. CONTENT PRIORITIZATION

Do not show everything with equal prominence.

For every component ask: "Does the user need this NOW?"

- If yes → prominent
- If useful but secondary → normal
- If rarely needed → compact, expandable, or secondary
- If unnecessary → remove it

Avoid information overload.

## 9. SPACING SYSTEM

Use a consistent spacing scale throughout the application.

Preferred rhythm: 4px, 8px, 12px, 16px, 24px, 32px

Use spacing to communicate relationships:

- Small spacing → related elements
- Medium spacing → different content within a section
- Large spacing → separate major sections

Do not use random padding values screen-by-screen without reason.

## 10. COMPONENT CONSISTENCY

Equivalent components must look and behave consistently:

- All search fields → same structure
- All form fields → same structure
- All primary buttons → same structure
- All cards → consistent radius/elevation/border treatment
- All dialogs → consistent hierarchy
- All empty states → consistent pattern
- All loading states → consistent pattern

Do not create a new visual style every time a new screen is added.

## 11. TYPOGRAPHY HIERARCHY

Use the existing Pinoy POS typography system consistently.

Establish clear roles: Display, Page title, Section title, Body, Label, Caption, Metadata.

Important values such as ₱10.00, Total Sales, Transaction Count, Order Total may receive stronger typography.

Do not use oversized text everywhere.

Do not use tiny text simply to fit more information.

Typography must remain readable on small phones.

## 12. COLOR SEMANTICS

Use the global Pinoy POS theme.

Colors must have semantic meaning:

- PRIMARY → main actions / brand
- SUCCESS → paid / completed / available
- WARNING → pending / attention
- ERROR/DANGER → failed / destructive
- INFO → information / guidance
- NEUTRAL → secondary information
- SURFACE → cards / panels
- BACKGROUND → page background

Never introduce arbitrary colors just because they look attractive on one screen.

Every color must work in BOTH Light Mode and Dark Mode.

## 13. DARK MODE / LIGHT MODE

Every screen must support both themes.

Audit:

- text contrast
- icon contrast
- card surfaces
- borders
- dividers
- buttons
- selected states
- disabled states
- input fields
- dialogs
- charts
- badges
- empty states
- images/placeholders

Do not hardcode colors inside individual widgets when a global theme token should be used.

## 14. CONTRAST & VISIBILITY

Important information must remain immediately visible.

Do not use:

- low-contrast text
- barely visible borders
- overly muted primary actions
- dark text on dark surfaces
- light text on light surfaces
- colored text without sufficient contrast

Check visibility in both light and dark mode.

## 15. CARDS

Cards should group meaningful information.

Do not put every tiny piece of information inside a separate card.

Use cards when they improve grouping or scanning.

Avoid CARD CARD CARD CARD CARD CARD with excessive nesting.

Use whitespace and sections when a card is unnecessary.

## 16. FORMS

Forms must have:

Label
↓
Input
↓
Supporting/validation message

Do not rely entirely on placeholder text to explain a field.

Required fields must clearly indicate that they are required.

Optional fields should be clearly distinguishable.

Validation must be understandable and shown near the relevant field when appropriate.

## 17. VALIDATION

UI validation must reflect actual application configuration.

Never hardcode "optional" or "required" if the application settings determine the behavior.

For example:

- Payment Settings: Customer Name = Required → POS with empty Customer Name MUST BLOCK CHECKOUT
- Payment Settings: Customer Name = Optional → POS with empty Customer Name MUST ALLOW CHECKOUT

Configuration-driven behavior must actually flow from:

Settings → Provider/Controller → Service → Repository → Database → UI/business validation

## 18. TOUCH TARGETS

Interactive controls must be comfortable to use on phones.

Prioritize touchability for: buttons, icons, quantity controls, product cards, payment methods, navigation, checkboxes, dropdowns, filters.

Do not make controls tiny simply to fit more content.

## 19. SCROLLING

Scrolling must be intentional.

Avoid unnecessary nested scroll views.

Audit for:

- RenderFlex overflow
- horizontal overflow
- clipped content
- inaccessible bottom buttons
- keyboard covering fields
- nested scrolling conflicts
- fixed-height containers trapping content

On portrait phones, the user should be able to naturally scroll through long content.

## 20. KEYBOARD AWARENESS

When the keyboard appears:

- focused fields must remain visible
- buttons must remain reachable
- content must not overflow
- dialogs must adapt
- search screens must remain usable
- payment fields must remain accessible

Never allow the keyboard to hide the primary action.

## 21. EMPTY STATES

Every data-driven screen needs a proper empty state.

Examples:

- No products: "No products yet."
- No sales: "No sales for this date range."
- Empty cart: "Your cart is empty."
- Empty Trash: "Trash is empty."
- Search with no result: "No matching records found."

Do not show a blank screen.

Do not confuse "No data exists" with "No search results."

## 22. LOADING STATES

Every asynchronous screen must have an intentional loading state.

Avoid sudden blank screens.

Use appropriate progress indicators, skeletons, or loading placeholders.

Do not make the UI appear broken while data is loading.

## 23. ERROR STATES

Errors must clearly communicate:

What happened + What the user can do

Prefer clear dialogs for important errors according to the existing Pinoy POS UX convention.

Avoid technical messages such as raw exceptions or database errors.

## 24. DIALOG RULE

Dialogs should be used for:

- important validation
- destructive confirmation
- critical errors
- successful completion when confirmation is meaningful
- actions requiring user attention

Do not use dialogs for every minor interaction.

Do not allow dialogs to become unnecessarily large or crowded.

## 25. DESTRUCTIVE ACTIONS

Destructive actions must be clearly separated from normal actions.

Delete, Permanent Delete, Void, Clear Cart must not be visually confused with Save, Add, Continue, Pay.

IMPORTANT: Removing an item from the POS cart is NOT the same as deleting a product.

- Cart removal → remove from temporary cart state
- Product deletion → product CRUD/deletion workflow

Do not mix these flows.

## 26. POS CART

Cart items should show:

- Product thumbnail
- Product name
- Price
- Quantity
- Quantity controls
- Subtotal
- Remove action

If the product has no image → show a clean product icon placeholder. Never show broken-image UI.

Cart removal must directly remove the item from the cart. Do NOT move cart items to Trash.

Clear Cart must directly clear temporary cart state.

## 27. PAYMENT SCREENS

Payment screens must prioritize:

1. Order summary
2. Total amount
3. Payment method
4. Required information
5. Payment input/instructions
6. Confirmation
7. Completion action

The amount must be immediately visible.

For QR payments:

Payment purpose
↓
Total amount
↓
QR
↓
Instructions
↓
Customer/reference information
↓
Confirm payment

Do not duplicate the QR unnecessarily.

Do not make supporting information more visually prominent than the payment amount or primary action.

## 28. SALES SCREENS

Sales screens must be easy to scan.

- Desktop/tablet → tables can be used when appropriate.
- Portrait phone → use responsive cards/list items.

Prioritize: Receipt number, Date/time, Customer, Payment method, Total, Status.

Detailed information can appear after tapping the transaction.

## 29. SEARCH & FILTERS

Search should be visually easy to find.

Avoid excessive filters.

Use filtering only when it genuinely helps the user's task.

For Trash specifically: ONE UNIFIED TRASH LIST + SEARCH. Do not create unnecessary user-based Trash tabs.

## 30. DASHBOARDS

Dashboards must prioritize actionable information.

Recommended hierarchy:

Key metrics
↓
Important trends
↓
Recent activity
↓
Secondary analytics

Do not fill dashboards with charts simply to make them look sophisticated.

Every chart must answer a useful question.

Date filtering must affect ALL date-dependent dashboard data.

If a selected date range contains no data → show zero/empty states. Never display stale data from another date range.

## 31. RECEIPT NUMBERS

Receipt numbers should be easy to recognize and search.

Use the global receipt pattern: `YYYYMMDD-NNNN` (e.g. `20260908-0001`).

The same receipt number must remain consistent across: POS transaction, Global Sales, transaction details, generated receipt, printed receipt, and search.

## 32. ICONOGRAPHY

Use the existing icon system consistently.

Icons should:

- communicate meaning
- support labels
- maintain consistent sizing
- not replace important text when meaning would be unclear

Do not use decorative icons everywhere.

## 33. VISUAL RHYTHM

Every screen should have consistent alignment, spacing, card treatment, icon sizing, typography, button sizing, and section separation.

If two screens perform similar tasks, their visual language should feel related.

## 34. REDUCE UI NOISE

Before adding a component, ask: "Does this improve understanding or action?" If not → remove it.

Avoid:

- unnecessary borders
- excessive shadows
- excessive badges
- redundant labels
- duplicate information
- excessive cards
- unnecessary animations
- decorative elements that compete with primary content

Modern UI should feel intentional, not crowded.

## 35. MICRO-INTERACTIONS

Use subtle feedback for important interactions: selection, successful save, add-to-cart, payment processing, payment success, restore, delete.

Animations must be short, purposeful, and subtle.

Never allow animation to slow down a high-frequency POS workflow.

## 36. ACCESSIBILITY

Audit:

- text contrast
- readable font sizes
- touch target sizes
- icon meaning
- focus states
- error visibility
- selected states
- dark/light contrast

Do not communicate important information through color alone.

## 37. CONSISTENCY ACROSS ROLES

Owner, Admin, Staff, and any other supported role must use the same global design language.

Role-specific functionality may differ. The design system must not.

## 38. DO NOT REDESIGN BACKEND LOGIC

UI modernization must not unnecessarily modify:

- database structure
- business rules
- API contracts
- authentication
- transaction logic
- inventory logic
- permissions

Only modify non-UI logic when required to correctly connect an existing UI feature to its existing functionality.

## 39. UI AUDIT BEFORE MODIFYING

Before changing any screen:

1. Inspect the existing implementation.
2. Identify the current functionality.
3. Identify the user's primary task.
4. Identify hierarchy problems.
5. Identify visibility problems.
6. Identify layout problems.
7. Identify responsive problems.
8. Identify interaction problems.
9. Identify accessibility problems.
10. Identify theme problems.
11. Identify unnecessary content.
12. Then modify the UI.

Do not blindly rewrite screens.

## 40. FINAL UI QUALITY CHECK

Before considering ANY screen complete, verify:

- [ ] Clear information hierarchy
- [ ] Clear primary action
- [ ] Logical content grouping
- [ ] Good visual hierarchy
- [ ] Good visibility
- [ ] Natural Z/F reading flow
- [ ] Correct spacing
- [ ] Consistent typography
- [ ] Consistent icons
- [ ] Correct semantic colors
- [ ] Light mode works
- [ ] Dark mode works
- [ ] Phone portrait works
- [ ] Tablet works
- [ ] Desktop works
- [ ] No horizontal overflow
- [ ] No unnecessary nested scrolling
- [ ] Keyboard does not hide content
- [ ] Touch targets are usable
- [ ] Loading state works
- [ ] Empty state works
- [ ] Error state works
- [ ] Validation is clear
- [ ] Destructive actions are clear
- [ ] Existing functionality still works
- [ ] No unnecessary UI elements
- [ ] Screen feels consistent with the rest of Pinoy POS

FINAL PRINCIPLE:

Do not ask: "How can we fit everything on this screen?"

Ask: "What does the user need first, what do they need next, and what can be safely secondary?"

The goal is not to make Pinoy POS look decorative. The goal is to make Pinoy POS: CLEAR, FAST, EASY TO SCAN, EASY TO LEARN, EASY TO OPERATE, RESPONSIVE, CONSISTENT, ACCESSIBLE, MODERN, PROFESSIONAL.

Apply this GLOBAL UI/UX RULE whenever creating, modifying, auditing, or fixing any Pinoy POS screen.

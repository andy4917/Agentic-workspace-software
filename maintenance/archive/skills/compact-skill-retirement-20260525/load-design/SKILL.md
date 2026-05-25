---
name: load-design
description: Create or refresh a repo-local DESIGN.md design contract for product, UI/UX, frontend, and design-system work. Use before visible frontend implementation, UI/UX planning, design direction, design-system alignment, product surface redesign, or when a repository needs a durable source of truth for brand, users, IA, visual language, components, accessibility, responsive behavior, interaction states, content voice, implementation constraints, and open design questions.
---

# Load Design

## Mission

Make repo-local `DESIGN.md` the design source of truth for frontend and product
UI work:

```text
existing repo evidence -> missing-context interview -> create/refresh DESIGN.md -> use DESIGN.md for implementation decisions
```

This skill creates a durable design contract. It is not a pixel-matching loop,
one-off screenshot critique, or replacement for rendered verification.

## Workflow

### 1. Discover Local Design Evidence

Inspect the repository before writing guidance. Look for:

- `DESIGN.md`, `docs/design*`, `docs/ux*`, `docs/frontend*`, `README.md`,
  product specs, PRDs, and issue notes.
- Routes, pages, layouts, components, stories, examples, demos, theme files,
  CSS variables, Tailwind/theme config, tokens, icons, and assets.
- Screenshots, mockups, brand files, logos, Storybook snapshots,
  visual-regression baselines, and reference notes.
- Accessibility, responsive, i18n, content, and platform constraints already
  encoded in code or docs.

Record evidence with file paths. Separate observed facts from design
inferences.

### 2. Interview Only For Missing Context

Ask concise questions only when repo evidence cannot answer design-critical
context. Prefer one focused round that closes the largest gaps:

- target users, personas, and jobs to be done;
- product/business goals and non-goals;
- brand personality and forbidden aesthetics;
- primary flows and information architecture;
- accessibility target, devices, browsers, and implementation constraints;
- external design assets or references absent from the repository.

If the user wants autonomous progress or cannot answer, create `DESIGN.md` with
explicit assumptions and open questions instead of blocking.

### 3. Create Or Refresh DESIGN.md

Preserve useful existing content, remove contradictions, and mark unknowns as
open questions. Keep the document actionable for implementers and reviewers.

Required structure:

```markdown
# Design

## Source of truth
- Status: Draft | Active | Needs refresh
- Last refreshed: YYYY-MM-DD
- Primary product surfaces:
- Evidence reviewed:

## Brand
- Personality:
- Trust signals:
- Avoid:

## Product goals
- Goals:
- Non-goals:
- Success signals:

## Personas and jobs
- Primary personas:
- User jobs:
- Key contexts of use:

## Information architecture
- Primary navigation:
- Core routes/screens:
- Content hierarchy:

## Design principles
- Principle 1:
- Principle 2:
- Tradeoffs:

## Visual language
- Color:
- Typography:
- Spacing/layout rhythm:
- Shape/radius/elevation:
- Motion:
- Imagery/iconography:

## Components
- Existing components to reuse:
- New/changed components:
- Variants and states:
- Token/component ownership:

## Accessibility
- Target standard:
- Keyboard/focus behavior:
- Contrast/readability:
- Screen-reader semantics:
- Reduced motion and sensory considerations:

## Responsive behavior
- Supported breakpoints/devices:
- Layout adaptations:
- Touch/hover differences:

## Interaction states
- Loading:
- Empty:
- Error:
- Success:
- Disabled:
- Offline/slow network, if applicable:

## Content voice
- Tone:
- Terminology:
- Microcopy rules:

## Implementation constraints
- Framework/styling system:
- Design-token constraints:
- Performance constraints:
- Compatibility constraints:
- Test/screenshot expectations:

## Open questions
- [ ] Question / owner / impact
```

### 4. Use DESIGN.md As The Decision Contract

For UI/UX/frontend work after the refresh:

- Cite relevant `DESIGN.md` sections before making design choices.
- Prefer existing components, tokens, and documented constraints.
- If implementation reveals a design contradiction, update `DESIGN.md` or add
  an open question before proceeding.
- Do not introduce a new design-system layer when repo-native patterns can be
  extended.
- When project instructions require an additional frontend quality directive,
  read it before implementation and treat `DESIGN.md` as the project-local
  contract that directive audits against.

### 5. Handoff To Implementation

Provide the implementation lane with:

- relevant `DESIGN.md` sections;
- repo evidence paths;
- assumptions and open questions;
- acceptance criteria for layout, states, accessibility, responsiveness, and
  rendered verification.

## Completion Checklist

Do not declare the design workflow complete until:

- existing design docs/assets/components/screenshots were inspected or noted as
  absent;
- missing product/design context was answered, assumed, or listed in open
  questions;
- repo-root `DESIGN.md` exists and contains all required sections;
- UI/UX/frontend recommendations cite `DESIGN.md` instead of unstated
  preferences;
- checks run and checks not run are reported with concrete reasons.

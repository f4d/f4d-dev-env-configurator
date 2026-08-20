---
id: frontend
always_apply: false
---
# Frontend

- Performance budgets are hard limits, checked in CI: LCP < 2.0s, TBT < 200ms, initial JS < 150KB gzipped.
- No client-side request waterfalls. Data needed for first paint is fetched server-side or in parallel.
- Accessibility: keyboard operable, visible focus, labeled controls, WCAG AA contrast. Interactive elements are real buttons and links.
- No layout shift from late-loading media — reserve dimensions.
- Loading, empty, and error states are built with the component, not added later.
- Never ship a component without its error state.

# Workspace App

This is the larger flagship verification app for `weiv`.

It is modeled as a release-readiness workspace:

- overview shows release health and approval metrics
- queue shows the current work items teams are triaging
- detail shows the selected item, save flow, and external webhook activity

The product story should be understandable to a human first, while still
serving as a framework coverage target.

It intentionally exercises:

- multi-level composition
- props across several boundaries
- child event emission
- local mutable state
- bounded shared state beyond the component boundary
- helper-derived display
- conditionals and loops
- named/default/fallback slots
- imported TS and JS helpers
- owned async callback mutation
- one intentionally unowned external-style callback registration

The app should stay readable enough to debug while still being meaningfully
broader than TodoMVC.

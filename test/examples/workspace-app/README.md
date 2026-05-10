# Workspace App

This is the larger flagship verification app for `weiv`.

Its job is framework coverage, not product realism.

It intentionally exercises:

- multi-level composition
- props across several boundaries
- child event emission
- local mutable state
- bounded proxy-tracked shared state
- helper-derived display
- conditionals and loops
- named/default/fallback slots
- imported TS and JS helpers
- owned async callback mutation
- one intentionally unowned external-style callback registration

The app should stay readable enough to debug while still being meaningfully
broader than TodoMVC.

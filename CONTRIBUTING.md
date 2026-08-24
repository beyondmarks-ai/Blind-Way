# Contributing

Thank you for improving Blind Way. Accessibility and emergency reliability are release requirements, not optional polish.

## Development workflow

1. Create a focused branch from `main`.
2. Keep credentials and personal data out of commits; use the provided example files.
3. Add or update tests for behavioural changes.
4. Run the Flutter and backend verification commands documented in `README.md`.
5. Open a pull request explaining user impact, accessibility considerations, failure behaviour, and manual device testing.

Do not reduce emergency cancellation safeguards, authorization checks, encrypted storage, or privacy retention controls without an explicit security review. UI changes must remain usable with TalkBack, large text, high contrast, and touch exploration.

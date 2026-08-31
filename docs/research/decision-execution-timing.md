# Decision and execution timing contract

A historical decision timestamp and the eventual transaction timestamp are different events.

For a pre-open decision such as `2021-04-01 00:00 Asia/Shanghai`:

- the valuation and Reverse DCF reference price is the latest close whose `available_at` is not later than the decision timestamp, normally the 2021-03-31 close;
- the simulated transaction uses the next eligible session's open, normally the 2021-04-01 open, plus configured slippage and fees;
- the 2021-04-01 close is forbidden in the decision information set because it did not yet exist;
- the next-session open is stored as an execution outcome, not as a Phase-A assumption.

This separation applies to every A/H decision cohort. A run that mixes same-day close data into a pre-open decision fails the PIT leakage test.

# Native Tencent/BYD validation matrix

| Validation | Tencent | BYD |
|---|---|---|
| Uses shared deterministic FCFF engine | Yes | Yes |
| Uses company-appropriate wrapper | Platform FCFF + SOTP | Manufacturing value-driver FCFF |
| Three complete scenarios | Yes | Yes |
| Reverse solve reuses forward model | Yes | Yes |
| Five-year holding value | Yes | Yes |
| 15% target entry price | Yes | Yes |
| Frozen input/output hashes | Yes | Yes |
| Compared with legacy base value | Yes, gap preserved | Yes, gap preserved |
| Automatic allocation allowed | No | No |
| Reason allocation is blocked | Filing bytes, price and FX are provisional | Filing bytes, price and EBIT bridge are provisional |

The tests intentionally freeze economically uncomfortable outputs. BYD's negative explicit-period FCFF and terminal-value share above 100% remain visible because they diagnose the reinvestment burden rather than a software error.

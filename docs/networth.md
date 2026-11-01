# networth.json: the Net Worth tab's data file

Compass's Net Worth tab shows a summary of the PMS/AIF **Portfolio Tracker** artifact. The
phone cannot read claude.ai artifacts, so after each tracker refresh (twice a month) a
scheduled task on the Mac writes a small summary file into Compass's private iCloud
Documents folder, and every device picks it up from there.

**Never commit a real networth.json to this repository.** The example below uses made-up
numbers.

## Where it goes

```
~/Library/Mobile Documents/iCloud~com~matodoapp~todo/Documents/networth.json
```

The folder appears (with a README.txt) the first time Compass 3.0 opens the Net Worth tab on
a device signed in to the same iCloud account. In Finder it shows under iCloud Drive as
"Compass".

## Producer

The Mac task reads the latest Portfolio Tracker artifact and fills in the fields below from its
headline and summary table. Keep `history` cumulative: read the existing file first and append
one point per refresh (replace the point if the same `refreshedAt` runs twice).

## Format

Amounts are ₹ crore. Percentages are plain numbers (10.73 means 10.73%). Dates are
`yyyy-MM-dd`. Fields marked optional may be omitted.

```json
{
  "asOf": "2026-09-30",
  "refreshedAt": "2026-10-18",
  "totals": {
    "netInvestedCr": 100.00,
    "fmvCr": 120.00,
    "gainCr": 20.00,
    "lifetimeGainPct": 20.0,
    "blendedIrrPct": 11.0,
    "blendedIrrInclCashPct": 9.0,
    "vsNifty500Cr": 2.5
  },
  "allocation": [
    { "name": "Equity / AIF", "pct": 50.0 },
    { "name": "Parked cash", "pct": 35.0 },
    { "name": "Debt", "pct": 10.0 },
    { "name": "Multi-asset", "pct": 5.0 }
  ],
  "segments": [
    { "name": "Equity", "netInvestedCr": 50.0, "fmvCr": 60.0, "irrPct": 10.5, "note": "8 PMS/AIF + 2 MF" }
  ],
  "managers": [
    { "name": "Manager A", "type": "PMS", "fmvCr": 15.0, "gainCr": 4.0, "irrPct": 16.0, "vsNifty500Cr": 1.2, "asOf": "2026-09-30" }
  ],
  "decisions": [
    { "title": "#10 Manager fee change", "status": "due <=30d", "nextDate": "2026-10-22" }
  ],
  "history": [
    { "date": "2026-10-05", "fmvCr": 118.0, "netInvestedCr": 99.0 },
    { "date": "2026-10-18", "fmvCr": 120.0, "netInvestedCr": 100.0 }
  ]
}
```

Optional: `totals.blendedIrrInclCashPct`, `totals.vsNifty500Cr`, `segments[].irrPct`,
`segments[].note`, `managers[].irrPct`, `managers[].vsNifty500Cr`, `managers[].asOf`,
`decisions[].nextDate`, `history[].netInvestedCr`.

## Monthly scorecard fields (3.0 build 21+)

All optional; the Net Worth tab hides a section when its fields are missing.

- `period`: the statement month, e.g. "September 2026".
- `monthSummary`: two or three sentences on the month against the market and what changed.
- `benchmark`: `{name, monthPct, oneYearPct}`, e.g. BSE 500 TRI −5.57 / −2.33.
- per manager: `monthPct`, `oneYearPct`, `verdict` (strong | steady | watch | lagging | new |
  cash), `why` (one line with the numbers), `action` (Add | Hold | Reduce | Exit | Switch),
  `decisionRef` (e.g. "#5").
- per decision: `kind` (add | exit | watch | fees | admin) and `needsDecision` (true when the
  tracker says it fired or is due within 30 days).
- `deployment`: `{title, targetCr, items: [{name, plannedCr, doneCr}]}` for a running plan.

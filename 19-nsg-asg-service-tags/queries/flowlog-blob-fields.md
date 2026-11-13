# Reading one flow tuple by hand

NSG flow log version 2 writes each flow as one comma separated string inside `flowTuples`:

```
1542110377,10.30.1.10,10.30.2.10,49152,8080,T,I,A,B,,,,
```

| Position | Field | Value here |
|---|---|---|
| 1 | time (Unix epoch seconds, UTC) | 1542110377 |
| 2 | source IP | 10.30.1.10 |
| 3 | destination IP | 10.30.2.10 |
| 4 | source port | 49152 |
| 5 | destination port | 8080 |
| 6 | protocol (T = TCP, U = UDP) | T |
| 7 | direction (I = inbound, O = outbound) | I |
| 8 | decision (A = allowed, D = denied) | A |
| 9 | flow state (B begin, C continuing, E end; version 2) | B |
| 10-13 | packets and bytes, source to destination and back (version 2; empty at state B) | empty |

Virtual network flow logs use a similar tuple with differences (a numeric protocol, an extra state for
denied flows, an encryption field). Check the current Microsoft docs for the exact layout before you parse them.

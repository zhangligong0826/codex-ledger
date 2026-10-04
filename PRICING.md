# Estimated API cost

This is an offline **USD equivalent at Standard API rates**, not a bill, subscription spend, account balance or historical invoice. No API key or network request is used. Opening the pricing link in a browser is a user action.

The bundled prices were verified on **2026-10-04** against the [official Standard pricing table](https://developers.openai.com/api/docs/pricing). The explicitly supported GPT-5.5 snapshot is documented on its [model page](https://developers.openai.com/api/docs/models/gpt-5.5). The complete table lives in `Common/prices.json`; undocumented models and aliases remain unpriced. Future price changes require an app update. GPT-5.6 Sol currently uses the published promotional price.

For each deduplicated response:

```text
USD = ((input − cached input) × input rate
       + cached input × cached rate
       + output × output rate) / 1,000,000
```

Reasoning is an output subset and is not charged again. Supported long-context models use double input/cached-input rates and 1.5 times output rates when that response's input exceeds 272,000 tokens. Aggregating multiple short responses never triggers a long-context premium. Legacy cumulative deltas are treated as confirmed response usage only if they match the logged last-response usage; otherwise short-context rates are used and the affected token count is retained as **Context unverified**.

Logs do not provide enough information to reproduce all billing rules. Cache-write premiums, service-tier differences (Fast, Batch, Flex and others), regional processing, tool charges and taxes are not included. History is repriced with this single snapshot, rather than rates on each historical date. Prices for missing and internal model names are not inferred from similar names.

The amount is the sum for known prices. `*` marks partial coverage, with unpriced tokens shown in the details; entirely unpriced usage displays **Unpriced**, while genuinely empty usage displays **$0.00**. Sub-cent amounts display **<$0.01**. Calculations and CSV values retain Decimal precision; the UI rounds only for display, so adding individually rounded rows can differ by a cent from the rounded total.

Project, global conversation, project-scoped conversation, task and model views aggregate the same per-response cost. Matched child agents follow the existing parent-task attribution and deduplication. All CSV types append estimated USD, priced/unpriced tokens, context-unverified tokens, price verification date and pricing basis. Unknown monetary amounts are blank in CSV, not zero.

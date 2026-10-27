# Writing dosi/model.yaml — shapes to start from

The extension contract, [datus-contract.yaml](datus-contract.yaml), is the
authority on every DATUS key: read a capability's block before using it.
This page only shows the layering on one small model. More complete models
are in dosi's examples (the `examples_dir` in `dosi info --format json`),
and every key is explained at
https://dosi.datus.ai/datus-extensions/.

Replace `<dialect>` with the warehouse's expression dialect (`POSTGRESQL`,
`SNOWFLAKE`, …; `ANSI_SQL` works everywhere) and `<v>` with the contract's
version (`envelope.version.generated_value`, e.g. `1.12`).

```yaml
version: 0.2.0.dev0
semantic_model:
  - name: sales
    description: Monthly sales by region
    datasets:
      - name: orders                          # snake_case, unique
        source: shop.orders                   # the table, as the warehouse names it
        fields:
          - name: order_id                    # an identifier: queryable, not offered as a grouping
            expression: {dialects: [{dialect: <dialect>, expression: order_id}]}
            custom_extensions: [{vendor_name: DATUS, data: '{"v":"<v>","is_dimension":false}'}]
          - name: customer_id
            expression: {dialects: [{dialect: <dialect>, expression: customer_id}]}
            custom_extensions: [{vendor_name: DATUS, data: '{"v":"<v>","is_dimension":false}'}]
          - name: region
            expression: {dialects: [{dialect: <dialect>, expression: region}]}
          - name: month                       # business time, stored as text 'YYYY-MM'
            expression: {dialects: [{dialect: <dialect>, expression: order_month}]}
            dimension: {is_time: true}
            custom_extensions:
              - vendor_name: DATUS
                data: '{"v":"<v>","requires":["time"],"time":{"format":"%Y-%m","storage":"string","granularity":"month"}}'
          - name: amount
            expression: {dialects: [{dialect: <dialect>, expression: amount}]}
          - name: status
            expression: {dialects: [{dialect: <dialect>, expression: status}]}
    metrics:
      # base: one aggregate, durable conditions in CASE WHEN
      - name: revenue
        description: Amount of completed orders (cancelled ones excluded)
        expression: {dialects: [{dialect: <dialect>, expression: "SUM(CASE WHEN orders.status = 'completed' THEN orders.amount END)"}]}
      - name: order_count
        description: Number of completed orders
        expression: {dialects: [{dialect: <dialect>, expression: "COUNT(DISTINCT CASE WHEN orders.status = 'completed' THEN orders.order_id END)"}]}
      # derived: compose metrics by name; `expression` is the expansion, written by dosi-fill-derived
      - name: avg_order_value
        description: Average amount of a completed order
        expression: {dialects: [{dialect: <dialect>, expression: "SUM(CASE WHEN orders.status = 'completed' THEN orders.amount END) / COUNT(DISTINCT CASE WHEN orders.status = 'completed' THEN orders.order_id END)"}]}
        custom_extensions:
          - vendor_name: DATUS
            data: '{"v":"<v>","derive":{"type":"compose","expr":"revenue / order_count"}}'
      # window: rank regions within each month (query by month and region)
      - name: revenue_rank
        description: Rank of the region by revenue within the month, 1 = highest
        expression: {dialects: [{dialect: <dialect>, expression: "SUM(CASE WHEN orders.status = 'completed' THEN orders.amount END)"}]}
        custom_extensions:
          - vendor_name: DATUS
            data: '{"v":"<v>","window":{"base":"revenue","rank":{"function":"rank","order":{"by":"value","direction":"desc"},"partition":{"mode":"query_dimensions_except","exclude":["orders.region"]}}}}'
      # composed over the window: derive.expr names the rank, so it runs after ranking
      - name: is_top_region
        description: 1 when the region is among the month's top 3 by revenue, else 0
        expression: {dialects: [{dialect: <dialect>, expression: "CASE WHEN SUM(CASE WHEN orders.status = 'completed' THEN orders.amount END) <= 3 THEN 1 ELSE 0 END"}]}
        custom_extensions:
          - vendor_name: DATUS
            data: '{"v":"<v>","derive":{"type":"compose","expr":"CASE WHEN revenue_rank <= 3 THEN 1 ELSE 0 END"}}'
```

What the layers buy: `is_top_region` reads `revenue_rank`, which reads
`revenue`. Change the definition of revenue once and the rank and flag
follow. Copying the formula into each, or computing the rank in a dataset's
SQL, loses that, and the model can no longer be queried at another grain.

Points that trip people up:

- Columns in metric expressions are qualified `dataset.field`.
- `derive.expr` uses metric names; `expression` is the same formula with the
  names expanded (same filters, DISTINCT and NULL handling). For a derive
  over a window it is only the approximation validation needs. Do not
  expand it by hand: write a placeholder aggregate and run
  `dosi-fill-derived`.
- A window's `partition.exclude` lists dimensions every query of it must
  group by (here `orders.region`).
- Relationships are many → one (`from` = the many side), with
  `from_columns` / `to_columns`; declare a `primary_key` only from evidence.
- A dataset `source` may be a SQL query only when the model cannot express
  the row set natively; say why in its `description`.
- A field's `expression` is SQL over its dataset's own columns. It cannot
  name another field (the warehouse rejects that at query time, after
  validation passed) and cannot hold a subquery. A value that needs either
  is a column of a dataset whose `source` is SQL.
- A window cannot read a D-LOD field: a per-customer value that a region
  ranks or averages over is a column of a dataset whose source is grouped by
  customer, not a `fixed(...)` field.

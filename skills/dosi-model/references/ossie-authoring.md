# Writing an Apache Ossie model for dosi

A complete minimal model (the shape `dosi validate` accepts):

```yaml
version: "0.2.0.dev0"

semantic_model:
  - name: sales
    description: Orders, customers and products
    datasets:
      - name: orders                     # snake_case, unique
        source: analytics.marts.orders   # the physical table, as the warehouse names it
        primary_key: [order_id]
        fields:
          - name: order_id
            expression: {dialects: [{dialect: ANSI_SQL, expression: order_id}]}
          - name: customer_id
            expression: {dialects: [{dialect: ANSI_SQL, expression: customer_id}]}
          - name: order_date
            expression: {dialects: [{dialect: ANSI_SQL, expression: order_date}]}
            dimension:
              is_time: true              # makes it a time dimension (grain-able)
          - name: status
            expression: {dialects: [{dialect: ANSI_SQL, expression: status}]}
          - name: amount
            expression: {dialects: [{dialect: ANSI_SQL, expression: amount}]}

      - name: customers
        source: analytics.marts.customers
        primary_key: [customer_id]
        fields:
          - name: customer_id
            expression: {dialects: [{dialect: ANSI_SQL, expression: customer_id}]}
          - name: region
            expression: {dialects: [{dialect: ANSI_SQL, expression: region}]}

    relationships:                       # many → one, from the fact to the dimension
      - name: orders_to_customers
        from: orders
        to: customers
        from_columns: [customer_id]
        to_columns: [customer_id]

    metrics:
      - name: revenue
        description: Completed order amount, refunds excluded
        expression:
          dialects:
            - dialect: ANSI_SQL
              expression: SUM(CASE WHEN orders.status = 'completed' THEN orders.amount END)
      - name: order_count
        description: Number of orders
        expression: {dialects: [{dialect: ANSI_SQL, expression: COUNT(orders.order_id)}]}
      - name: avg_order_value
        description: Revenue per order
        expression: {dialects: [{dialect: ANSI_SQL, expression: SUM(orders.amount) / COUNT(orders.order_id)}]}
```

## Rules dosi enforces

- **Metric kinds are inferred** from the expression: one aggregate
  (`SUM/COUNT/COUNT(DISTINCT)/AVG/MIN/MAX`) = aggregate; aggregate ÷ aggregate
  = ratio; any other combination of aggregates = expression. Write the
  arithmetic, dosi plans it correctly (no double counting across joins).
- **Columns in metrics are qualified** `dataset.field`.
- **Relationships** are many→one (`from` = the many side). Two paths between
  the same datasets are allowed; queries then name the path
  (`relationship_name.field`).
- **Time**: mark date/timestamp fields `dimension: {is_time: true}`. Queries
  group by `dataset.field:month` or `metric_time:week`.
- **Source** is the table name as the warehouse resolves it (DuckDB local
  files: `main.<table>`).
- `primary_key` on every dataset that is the "one" side of a relationship.

## What to model first

1. The fact table behind the user's question, with its date column as a time
   dimension.
2. The dimension tables the question groups or filters by, with relationships.
3. 3–8 metrics: the ones the question needs, plus obvious companions
   (count, sum of the main amount, distinct count of the main entity).

Ambiguities worth asking (Q4): refunds/negative amounts, cancelled or test
rows, which of two date columns is "the" date, which of two join paths is the
default, gross vs net.

Larger models and every extension (windows, parameters, semi-additive
metrics) are documented on the dosi docs site; validate after every change.

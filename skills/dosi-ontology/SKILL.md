---
name: dosi-ontology
description: Build or use an Apache Ossie ontology (dosi/ontology.yaml) — business concepts such as Customer, Order, Product, their relationships and roles — and ask questions by concept path. Use only when the user asks about an ontology, business concepts or entity relationships, or has just accepted the plugin's offer to build one.
allowed-tools:
  - Bash(dosi *)
  - mcp__plugin_dosi_dosi__describe
  - mcp__plugin_dosi_dosi__paths
  - mcp__plugin_dosi_dosi__select
  - mcp__plugin_dosi_dosi__run_query
  - mcp__plugin_dosi_dosi__list_datasets
  - mcp__plugin_dosi_dosi__validate_model
---

# Ontology: questions by business concept

Write to the user in the language they write in, every progress line
included.

An ontology names the business concepts behind the model (Customer, Order,
Product), how they relate ("an Order is placed by a Customer"), and which
join each relationship means. It makes entity questions precise when two
tables are connected in more than one way.

`dosi` is on PATH in Claude Code; in other agents it is in the plugin's
`bin/` folder, two levels above this file. Use business terms with the
user; concept paths are for tool calls.

## Before building

Unless the user just asked for it, say in two or three sentences what it
buys them, using one of their own questions (e.g. "which region's customers
buy the most electronics" goes from orders to customers and to products;
the ontology names those links, so such questions always join the same
way). It adds two files and changes no data or metrics.

## Build

Do it in this conversation, one line before each step. (The
dosi-ontologist subagent runs the same steps in the background; use it only
when the user asks for that.)

1. Read the model: `list_datasets` and the relationships in
   `dosi/model.yaml`. Read the references with the file tools (Read, Grep),
   not the shell. Start from the complete example in
   [references/](references/) (`example-orders.ontology.yaml`,
   `example-orders.mapping.yaml`, `model-orders.yaml`) and the rules in
   [references/ontology-authoring.md](references/ontology-authoring.md).
2. Write `dosi/ontology.yaml` (concepts and named relationships in the
   user's vocabulary; parallel links each get their own name) and
   `dosi/mapping.yaml` (which dataset key or column each concept and link
   is). Never edit the model for it.
3. Check: `dosi validate --format json` (Claude Code also validates every
   save), then `describe`, `describe` for each entity, `paths` between the
   pairs the user asked about, and one of the user's questions as a
   `select` on concept paths.
4. Ask at most 3 questions where the evidence allows several readings
   (multiplicity, names of parallel links, whether a notion like "key
   account" is a concept or a filter), the recommended reading first.
5. One line to the user: the ontology is ready, with its concepts and
   number of relationships.

## Use

dosi loads `dosi/ontology.yaml` and `dosi/mapping.yaml` by itself. Concept
paths work wherever fields do (CLI in brackets):

- `describe`: the concept catalog; with `name`, one concept in full
  (`dosi describe [Customer]`);
- `paths` with `from` / `to`: every named path between two concepts
  (`dosi paths --from Order --to Product`);
- `select` with `from: "Order"` and fields such as
  `Order.placed_by.region`, `Order.purchases.category`;
- `run_query` grouped by a concept path such as `Order.placed_by.region`.

`order_by` takes output column names, not concept paths. Refusals name the
repair in `suggested_retry`. The concept graph: the dosi-view skill.

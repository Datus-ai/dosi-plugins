---
name: dosi-ontology
description: Build or use an Apache Ossie ontology (dosi/ontology.yaml) — business concepts such as Customer, Order, Store, their relationships and roles — and ask questions by concept path. Use only when the user explicitly asks about an ontology / business concepts / entity relationships, or has just accepted the ontology suggestion from dosi-progress.
allowed-tools:
  - Bash(dosi *)
  - Bash(dosi-progress *)
---

# Ontology: questions by business concept

An ontology names the business concepts behind the model (Customer, Order,
Store), how they relate ("an Order is placed by a Customer", "shipped to a
Store"), and which join each relationship means. It makes entity questions
precise when two tables are connected in more than one way.

## Explain first (3 sentences, using the user's own question)

Before building anything, say what it buys them with an example from this
conversation, e.g.: 「你刚才问的"退货多的客户常去哪些门店"要经过订单→客户、
订单→门店两条关系。ontology 把这些关系起了业务名字，以后直接问
"Customer.frequent_store" 这类问题就不会走错路径。建一个大约需要几分钟，
过程中我最多问你 3 个问题。」

## Build

1. Delegate to the **dosi-ontologist** subagent (Agent tool,
   `subagent_type: "dosi:dosi-ontologist"`) with: the path `dosi/model.yaml`,
   the entity questions the user has asked so far, and their words for the
   concepts.
2. It returns the path `dosi/ontology.yaml`, a summary (concepts,
   relationships), and at most 3 ambiguities with candidates. Ask each with
   AskUserQuestion (**Q7**), recommended first, and apply the answers.
3. Check (the hook also validates every save):

   ```bash
   dosi --ontology dosi/ontology.yaml validate --format json
   dosi describe
   ```

4. One line to the user:
   `◆ ontology 已就绪：Customer、Order、Product、Store（4 个概念，5 条关系）`.

## Use

With `DOSI_ONTOLOGY` set (the session sets it once `dosi/ontology.yaml`
exists; in this session pass `--ontology dosi/ontology.yaml`):

```bash
dosi describe                         # concept catalog
dosi describe Customer                # one concept in full; every name it prints is pasteable
dosi paths --from Order --to Store    # every named path, with roles and hop counts
dosi select --format json --execute --from Customer \
  --fields Customer.id,Customer.name,Customer.places.shipped_to.name \
  --where "Customer.places.status = 'returned'"
dosi query --format json --execute --metrics revenue --group-by Order.placed_by.region
```

Concept paths work in `--from`, `--fields`, `--group-by`, `--where`,
`--time-dimension` and `--metrics` (derived metrics: `Concept.metric`).
`--order` takes output column names, not concept paths. Refusals name the
repair in `suggested_retry` — use it.

The concept graph: the **dosi-view** skill (`dosi lineage view`).

Syntax reference: [references/ontology-authoring.md](references/ontology-authoring.md).

## Close

At the end run `dosi-progress next`: append a `HINT:` line verbatim; ask an
`ASK:` line with AskUserQuestion and record the answer; add nothing otherwise.

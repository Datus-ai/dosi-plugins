# Writing an ontology for dosi (model-first)

> **Start from the complete example** in `${CLAUDE_PLUGIN_ROOT}/skills/dosi-ontology/references/`:
> `example-orders.ontology.yaml` (concepts), `example-orders.mapping.yaml` (mappings) and their
> model `model-orders.yaml` — validated, with value types, links and every mapping section.
> Copy its structure; do not browse `dosi info` examples.

Model-first, three files with one job each: `dosi/model.yaml` stays the
source of truth for tables, fields and joins; `dosi/ontology.yaml` holds the
concepts and their relationships, nothing else; `dosi/mapping.yaml` says
which dataset key or column each concept and relationship is, naming the
model's own datasets and fields. dosi loads all three (the CLI finds them in
`dosi/`; the MCP server follows them as they are written). Do not embed
`ontology_mappings` in the ontology: that layout is deprecated.

Complete small example (two concepts, two relationships between them — the
case an ontology exists for):

```yaml
version: 0.2.0.dev0
name: Flights
description: Flights and the airports they leave from and arrive at.

ontology:
  - concept: AirportCode
    type: ValueType
    extends: [String]
  - concept: Delay
    description: Minutes a flight left after its scheduled departure.
    type: ValueType
    extends: [Decimal]

  - concept: Airport
    type: EntityType
    identify_by: [code]
    relationships:
      - name: code
        roles: [{concept: AirportCode}]
        multiplicity: OneToOne
        verbalizes: ["{Airport} is identified by {AirportCode}"]

  - concept: Flight
    type: EntityType
    identify_by: [id]
    relationships:
      - name: id
        roles: [{concept: Integer}]
        multiplicity: OneToOne
        verbalizes: ["{Flight} is identified by {Integer}"]
      - name: departs_from
        roles: [{concept: Airport}]
        multiplicity: ManyToOne
        verbalizes: ["{Flight} departs from {Airport}"]
      - name: arrives_at
        roles: [{concept: Airport}]
        multiplicity: ManyToOne
        verbalizes: ["{Flight} arrives at {Airport}"]
      - name: departure_delay
        roles: [{concept: Delay}]
        multiplicity: ManyToOne
        verbalizes: ["{Flight} has {Delay} on departure"]
```

and the mapping, in its own file (`dosi/mapping.yaml`), binding those
concepts to the model's datasets and fields by name:

```yaml
version: 0.2.0.dev0
name: flights_mapping
ontology_ref: {name: Flights, iri: ./ontology.yaml}
semantic_model_ref: {name: flights_model, iri: ./model.yaml}   # = the semantic_model name in dosi/model.yaml
concept_mappings:
  - concept: Airport
    object_mappings:
      - referent_mappings: [{relationship: code, expression: airports.code}]
  - concept: Flight
    object_mappings:
      - referent_mappings: [{relationship: id, expression: flights.id}]
    link_mappings:
      - object_mapping: {referent_mappings: [{relationship: id, expression: flights.id}]}
        children:
          - object_mapping:
              concept: Airport
              referent_mappings: [{relationship: code, expression: flights.origin_code}]
            relationship: departs_from
          - object_mapping:
              concept: Airport
              referent_mappings: [{relationship: code, expression: flights.dest_code}]
            relationship: arrives_at
          - object_mapping: {concept: Delay, expression: flights.dep_delay}
            relationship: departure_delay
```

## Link direction (read before writing links)

A link is declared on the concept that holds the foreign key and is walked
many → one: `Order.placed_by.region`, never `Customer.places…`. dosi does
not walk one → many (it would fan out), and there is no inverse-link syntax
to look for — do not search the examples or the binary for one. To answer
"per customer" questions, group a metric that lives on `Order` by
`Order.placed_by.<property>`. A second verbalization such as
`'{Customer} places {Order}'` is documentation only.

## Building one from a model

1. **Entities** — one `EntityType` concept per business thing the user talks
   about (usually one per dataset with a primary key). `identify_by` = its key
   relationship. A key of several columns (a store in a given month) lists
   one relationship per column, and the mapping gives one referent each:

   ```yaml
   # ontology.yaml
   - concept: Store
     type: EntityType
     identify_by: [ month, code ]
     relationships:
     - { name: month, roles: [ { concept: MonthKey } ], multiplicity: ManyToOne }
     - { name: code, roles: [ { concept: StoreCode } ], multiplicity: ManyToOne }
   # mapping.yaml
   - concept: Store
     object_mappings:
     - referent_mappings:
       - { relationship: month, expression: store_month.month_key }
       - { relationship: code, expression: store_month.store_code }
   ```

   A link to such a concept (an order's store) names both parts the same
   way, as `referent_mappings` under the link's `object_mapping`.
2. **Value types** — `ValueType` concepts (extends `String`, `Integer`,
   `Decimal`, `Date`, …) for meaningful values (Delay, Amount, Region).
3. **Relationships** — one per many→one link, named as a verb phrase from the
   many side (`placed_by`, `shipped_to`, `departs_from`), with `verbalizes`
   in plain language. Two links to the same concept get two names — that is
   the point.
4. **Mappings** — in `dosi/mapping.yaml`: each concept to its dataset key,
   each link to the foreign-key column.
5. Validate, then `dosi describe` and `dosi paths --from A --to B` to check
   it reads the way the user talks.

Worth asking the user: multiplicity ("does a store belong to exactly one
region?"), names of parallel links ("ordering customer" vs "receiving
customer"), whether a derived notion ("key account") is a concept or just a
filter.

More: the bundled examples (the `examples_dir` in `dosi info --format
json`):
`ossie-mini-flights/` (smallest), `aviation/` (model-first, realistic),
`ossie-flights/` (the upstream reference ontology).

# Writing an ontology for dosi (model-first)

Model-first: `dosi/model.yaml` stays the source of truth for tables, fields
and joins; `dosi/ontology.yaml` adds concepts on top. Load both:
`dosi --model dosi/model.yaml --ontology dosi/ontology.yaml …` (the session
exports both). When `--model` is given it wins; the ontology's embedded
`semantic_model` only has to make its mapping expressions resolvable.

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

ontology_mappings:
  - name: flights_mapping
    semantic_model:
      name: flights_model            # = the semantic_model name in dosi/model.yaml
      datasets:
        - name: AIRPORT
          source: main.airports
          fields:
            - name: code
              expression: {dialects: [{dialect: ANSI_SQL, expression: code}]}
        - name: FLIGHT
          source: main.flights
          fields:
            - name: id
              expression: {dialects: [{dialect: ANSI_SQL, expression: id}]}
            - name: origin_code
              expression: {dialects: [{dialect: ANSI_SQL, expression: origin_code}]}
            - name: dest_code
              expression: {dialects: [{dialect: ANSI_SQL, expression: dest_code}]}
            - name: dep_delay
              expression: {dialects: [{dialect: ANSI_SQL, expression: dep_delay}]}
    concept_mappings:
      - concept: Airport
        object_mappings:
          - referent_mappings: [{relationship: code, expression: AIRPORT.code}]
      - concept: Flight
        object_mappings:
          - referent_mappings: [{relationship: id, expression: FLIGHT.id}]
        link_mappings:
          - object_mapping: {referent_mappings: [{relationship: id, expression: FLIGHT.id}]}
            children:
              - object_mapping:
                  concept: Airport
                  referent_mappings: [{relationship: code, expression: FLIGHT.origin_code}]
                relationship: departs_from
              - object_mapping:
                  concept: Airport
                  referent_mappings: [{relationship: code, expression: FLIGHT.dest_code}]
                relationship: arrives_at
              - object_mapping: {concept: Delay, expression: FLIGHT.dep_delay}
                relationship: departure_delay
```

## Building one from a model

1. **Entities** — one `EntityType` concept per business thing the user talks
   about (usually one per dataset with a primary key). `identify_by` = its key
   relationship.
2. **Value types** — `ValueType` concepts (extends `String`, `Integer`,
   `Decimal`, `Date`, …) for meaningful values (Delay, Amount, Region).
3. **Relationships** — one per many→one link, named as a verb phrase from the
   many side (`placed_by`, `shipped_to`, `departs_from`), with `verbalizes`
   in plain language. Two links to the same concept get two names — that is
   the point.
4. **Mappings** — map each concept to its dataset key and each link to the
   foreign-key column, under `ontology_mappings`.
5. Validate, then `dosi describe` and `dosi paths --from A --to B` to check
   it reads the way the user talks.

Worth asking the user (Q7): multiplicity ("一个门店属于一个区域吗？"), names
of parallel links ("下单客户" vs "收货客户"), whether a derived notion
("大客户") is a concept or just a filter.

More: the bundled examples (`dosi info --format json` → `examples_dir`):
`ossie-mini-flights/` (smallest), `aviation/` (model-first, realistic),
`ossie-flights/` (the upstream reference ontology).

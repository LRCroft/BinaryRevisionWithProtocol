# VSN Library — Python (reference implementation)

Language-native VSN-1 library for Python. This is the **reference
implementation**: it implements the frozen VSN-1 canonical binary grammar,
record/field framing, DIRECT-1 and EXTENTS-1 representation
materialization, marker-based recovery, and validation, and passes the
frozen byte vectors in `../TestVectors`.

## Status

**Conformant** for the frozen vectors and negative tests in `tests/`.

## Layout

```
vsn/
  __init__.py       package exports
  primitives.py     u16/u32/u64, uvarint, bool, UTF-8 (GR-08, GR-21..26)
  reader.py         streaming, bounds-checked cursor (GR-47 truncation)
  constants.py      frozen record/field/registry identifiers
  model.py          FileId/RevisionId/ObjectSerial identity types
  container.py      container parser (records, fields, objects, trailer)
  representations.py DIRECT-1 and EXTENTS-1 materialization
  api.py            VsnContainer high-level facade
  validate.py       structural/semantic/recovery validation layers
  recovery.py       marker-based crash recovery
  diff.py           derived object diff
  writer.py         canonical encoder
  transactions.py   staging/ExpectedRevisionId contract
  errors.py         frozen error registry + exceptions
  cli.py            command-line inspection tool
tests/
  test_vsn.py       frozen-vector, negative, and primitive tests
```

## Usage

```python
import vsn

c = vsn.open(open("file.vsn", "rb").read())
content = c.materialize(42)   # DIRECT-1 or EXTENTS-1 logical bytes
```

CLI:

```
python -m vsn.cli inspect file.vsn
python -m vsn.cli validate file.vsn
python -m vsn.cli recover file.vsn
python -m vsn.cli materialize file.vsn <object_serial>
```

## Tests

```
python -m unittest tests.test_vsn
```

## Conformance

Run the shared corpus from `../Conformance` or the unit tests above. All
frozen vectors (`DIRECT-01..03`, `EXT-01`, `EXT-02/03`) parse, validate,
recover to generation 1, and materialize to the expected logical bytes.

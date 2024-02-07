# SQL Support

## Supported Syntax Reference

### Introduction

The platform currently supports a limited subset of SQL. 

The SQL syntax is currently both CASE and whitespace sensitive (e.g. `SELECT` is valid, `SeLeCT` is not).

With the exception of the base `SELECT` against a data source, and any [data source supported scalar functions](#functions), _all_ query operations are performed in-platform.

### Basic Usage and SELECT

A basic query against a data source can be performed by `SELECT`ing against the relevant data source object.

To select all fields from a the table `table` data source `data_source`:

`SELECT d1.* FROM data_source.table d1`

`d1` in the query is the data source alias. Data source aliases are **REQUIRED** for all data sources in a query. 

SELECTed fields may be aliased, or not:

`SELECT d1.username AS user,d1.title FROM data_source.table d1`

any field which is not aliased, will be named after it's field name in the data source, _without_ the data source alias (i.e. `d1.title` will return as `title`, not `d1.title`).

Similarly, function calls may be aliased, or not:

`SELECT LOWER(d1.username) AS user,UPPER(d1.title) FROM data_source.table d1`

a non-aliased function call that gets pushed down to the data source will have the name the data source assigns, while a platform-based function executions will be named `func_position` (e.g. `upper_2`).

### JOINs

A single `LEFT`, `INNER`, or `RIGHT` join may be specified, using a single binary comparison as a JOIN condition:

`SELECT d1.*,d2.* FROM data_source.table d1 LEFT JOIN data_source_2.table2 d2 ON (d1.id = d2.id)`

`SELECT d1.*,d2.* FROM data_source.table d1 RIGHT JOIN data_source_2.table2 d2 ON (d1.id = d2.id)`

`SELECT d1.*,d2.* FROM data_source.table d1 INNER JOIN data_source_2.table2 d2 ON (d1.id = d2.id)`

See below for [Supported Comparison Operators](#supported-comparison-operators).

### WHERE

A single `WHERE` clause may be specified, using a single binary comparison as a WHERE condition:

`SELECT d1.*,d2.* FROM data_source.table d1 LEFT JOIN data_source_2.table2 d2 ON (d1.id = d2.id) WHERE d2.group_name = 'Test'`

The comparison may be to another field in the query, or to a string literal. Booleans are NOT supported.

See below for [Supported Comparison Operators](#supported-comparison-operators).

### LIMIT

A `LIMIT` clause may be specified to limit the number of results returned. Providing an offset is NOT supported:

`SELECT d1.*,d2.* FROM data_source.table d1 LEFT JOIN data_source_2.table2 d2 ON (d1.id = d2.id) WHERE d1.group_name = 'Test' LIMIT 1`

### GROUP BY

A `GROUP BY` clause may be specified for [aggregate functions](#functions), providing a single field to group on:

`SELECT d1.group_name,COUNT(d2.*) AS count FROM data_source.table d1 LEFT JOIN data_source_2.table2 d2 ON (d1.id = d2.id) GROUP BY d1.group_name`

### ORDER BY

A `ORDER BY` clause may be specified, providing a single field to sort on, and an optional direction (**ASC**ending or **DESC**ending):

`SELECT d1.group_name,COUNT(d2.*) AS count FROM data_source.table d1 LEFT JOIN data_source_2.table2 d2 ON (d1.id = d2.id) ORDER BY count DESC`

if a direction is not specified, it defaults to Ascending. The following queries are equivalent:

`SELECT d1.group_name,COUNT(d2.*) AS count FROM data_source.table d1 LEFT JOIN data_source_2.table2 d2 ON (d1.id = d2.id) ORDER BY count`

`SELECT d1.group_name,COUNT(d2.*) AS count FROM data_source.table d1 LEFT JOIN data_source_2.table2 d2 ON (d1.id = d2.id) ORDER BY count ASC`

## Supported Comparison Operators

The platform currently supports the following comparison operators:

  - Equals (`=`)
  - Not Equals (`!=`, `<>`)
  - Less Than or Equal (`<=`)
  - Greater Than or Equal (`>=`)
  - Greater Than (`>`)
  - Less Than (`<`)

Comparisons are performed with implicit casting where appropriate. 

## Functions

The platform currently supports the following SQL functions (see `PlatformFuncs` for the in-platform implementations):

|**Function**|**Type**|**Description**|**Usage**|**Platform Only?***|
|`LOWER`|Scalar|Lowercases the field value|`LOWER(d1.field)`|Yes|
|`UPPER`|Scalar|Uppercases the field value|`UPPER(d1.field)`|Yes|
|`COUNT`|Aggregate|Counts the (optionally grouped) field values|`COUNT(*)`,`COUNT(DISTINCT *)`, `COUNT(d1.field)`, `COUNT(DISTINCT d1.field)`|No|
|`AVG`|Aggregate|Averages the (optionally grouped) field values|`AVG(d1.field)`|No|
|`SUM`|Aggregate|Sums the (optionally grouped) field values|`SUM(d1.field)`|No|
|`CONCAT`|Scalar (Varargs)|Concatenates the listed fields and string literals|`CONCAT(d1.field,'string_literal',d2.field,...)`|No|
|`CONCAT_WS`|Scalar (Varargs)|Concatenates the listed fields and string literals, using the first parameter as a separator|`CONCAT_WS(d1.field,'string_literal',d2.field,...)`, `CONCAT_WS('separator','string_literal',d2.field,...)`|No|

If a function is marked Platform Only, all instances of the function are executed in-platform. Otherwise, execution at the data source or platform level is controlled by the [Data Source Function Support Module](extra_docs/data_sources.md).
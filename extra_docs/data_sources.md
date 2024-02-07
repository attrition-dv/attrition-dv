# Data Source Support

## Introduction

The platform is intended to provide generic support for a wide variety of data sources, and to facilitate easy development of additional data source connectors.

As this is an early version of the platform, the data source connector module APIs will likely undergo many future changes. 

All official connectors are currently maintained in tandem with the platform itself, and will benefit from additional features as they are added. 

## Connector Modules

In order to be used within the platform, each connector requires several modules:

- The **Connector Module** (e.g. `StandardODBCConnector`)
  - translates parsed query fragments into data source specific form
  -  connects to the underlying data source and performs any pre-fetching actions (e.g. opening an ODBC database connection)
  - prepares the **Result Wrapper**
- The **Function Support Module** (e.g. `PostgreSQLFuncs`)
  - verifies data source support of [supported platform functions](extra_docs/sql_support.md#functions)
  - translates query function fragments into the function string required by the underlying data source
  - multiple function support modules can exist for the same **Connector Module**
  - Any data source connector may use the `ForcePlatformFuncs` module to force all function calls to be executed at the platform level.
  - Currently only **SCALAR** functions will be sent to this module. Other functions are executed in-platform.
- The **Result Wrapper Module** (e.g. `ODBCResult`)
  - Responsible for passing information from the **Connector Module** to the **Result Handler**
  - Should provide all connection state and associated metadata required for the **Result Handler**
- The **Result Set Module** (implementation of `ResultSet` )
  - This is an implementation of the `ResultSet` protocol
  - Responsible for providing a `Stream` of the data source result, in a generic format expected by the rest of the platform

## Supported Data Sources

The following is a list of official data source connectors currently shipped with the platform.

To configure a connector:

- Edit `config/config.exs`
- Find the `connectors:` section under `:DV`
- Add the desired configuration definition inside the list in the following format (see the individual connector section):

```
{$connector_class,$data_source_type,$version,{$connector_module,[$additional_options],$function_support_module}}
```

e.g. 

```
config :DV,connectors: [{:web_api,"REST",1,{WebAPIConnector,[result_type: :json]},ForcePlatformFuncs}]
```

### Standard ODBC

|**Description**|Generic support for SQL-based ODBC drivers.|
|**Dependencies**|Requires the Linux ODBC driver for the desired database type (not included).|
|**Limitations**|Kerberos only.|
|**Class**|`:relational`|
|**Data Source Type**|Use Supported Data Source Name (e.g. `PostgreSQL`)|
|**Version**|Use Supported Data Source Name (e.g. `15`)|
|**Connector Module**|`StandardODBCConnector`|

**Additional Options:**

|**Option**|**Description**|
|**driver**|path to the Linux ODBC driver for the data source type.|
|**connection_string**|connection string to use when connecting to the underlying data source. Valid placeholders are **\$spn** (Kerberos SPN of `:client_uid`), **$hostname** (hostname), **\$database** (database name), **\$driver** (above driver path).|

**Function Support Modules:**

|**Module Name**|**Supported Data Source(s)**|
|`PostgreSQLFuncs`|PostgreSQL 15|
|`MariaDBFuncs`|MariaDB 11|

### Flat File

|**Description**|Generic support for JSON and delimited (e.g. CSV) flat files.|
|**Dependencies**|None.|
|**Limitations**|No authentication supported. Uses the (Linux) identity of the *Platform Server*.|
|**Class**|`:file`|
|**Data Source Type**|`JSON` (for JSON), `CSV` (for delimited).|
|**Version**|1|
|**Connector Module**|`FileConnector`|


**Additional Options:**

|**Option**|**Description**|
|**result_type**|`:json` (for JSON), `:csv` (for CSV).|

**Function Support Modules:** N/A.

### REST API

|**Description**|Generic support for HTTP-based data sources (e.g. REST APIs)|
|**Dependencies**|None.|
|**Limitations**|SPNEGO (GSSAPI) authentication only. GET requests only. No pagination or query specific parameter support. Only `JSON` responses are currently supported.|
|**Class**|`:web_api`|
|**Data Source Type**|`REST`|
|**Version**|1|
|**Connector Module**|`WebAPIConnector` |

**Additional Options:**

|**Option**|**Description**|
|**result_type**|`:json` (for JSON)|

**Function Support Modules:** N/A.

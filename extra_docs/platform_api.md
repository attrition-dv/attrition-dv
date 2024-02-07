# Platform Client APIs

This document covers Version 1 of the platform API.

This document uses the following terms:

|**Term**|**Definition**|
|**Category**| The area of functionality an API action relates to (e.g. Data Source, Model)|
|**Action**| The specific action being performed in the category (e.g. Add, Get)|
|**AUD**| API actions which modify the platform metadata. **A**dd, **U**pdate, and **D**elete| 

## Connect

The platform API supports both REST and WebSocket connections.

In both cases, the connection is established using SPNEGO (GSSAPI Kerberos) authentication.

### REST

To connect to the platform using REST, use either HTTP or HTTPS, based on your configuration settings:

- **HTTP:** `http://$hostname:$api_http_port/api/v1/$api_action`
- **HTTPS:** `https://$hostname:$api_https_port/api/v1/$api_action`

e.g. if the platform is configured to run HTTPS traffic via port 4431, and you want to use the Data Source -> Get All action, the URL would be: `https://$hostname:4431/api/v1/data_source/get`. 

The REST API expects either `GET` or `POST` operations, depending on the action. 

The REST API expects JSON formatted requests, and returns JSON formatted responses.

### WebSocket

To connect to the platform using a WebSocket, use either WS or WSS protocol, based on your configuration settings:

- **WS:** `ws://$hostname:$api_http_port/api/v1/client/open_websocket`
- **WSS:** `wss://$hostname:$api_https_port/api/v1/client/open_websocket`

e.g. if the platform is configured to run HTTPS traffic via port 4431, and you want to connect via secure WebSocket, the URL would be: `wss://$hostname:4431/api/v1/client/open_websocket`. 

The WebSocket API expects JSON formatted requests, and returns JSON formatted responses.

## Entitlement Model

API functionality is sorted into **Category** and **Action**. 

The platform entitlement model is based on ACLs that correlate mostly one-to-one to these actions. Each of these ACLS may be granted to a user or a group.

|**Category**|Data Source|
|**Action**|**Effect**|
|**Add**|Add a new data source.|
|**Update**|Edit an existing data source.|
|**Delete**|Delete an existing data source.|
|**Get**|List all data sources, and get specific data source details.|

|**Category**|Model|
|**Action**|**Effect**|
|**Add**|Add a new model|
|**Update**|Edit an existing model.|
|**Delete**|Delete an existing model.|
|**Get**|List all models, and get specific model details.|

|**Category**|Endpoint|
|**Action**|**Effect**|
|**Add**|Add a new endpoint.|
|**Update**|Edit an existing endpoint.|
|**Delete**|Delete an existing endpoint.|
|**Get**|List all endpoints, and get specific endpoint detail.s|
|**Run**|Run the endpoint (execute the underlying virtual model query).|

|**Category**|ACL|
|**Action**|**Effect**|
|**Update**|Edit all ACLs (there is no individual ACL change endpoint).|
|**Get**|List all endpoints, and get specific endpoint details.|

|**Category**|Request|
|**Action**|**Effect**|
|**Get**|List all requests, poll for a running request's data.|

|**Category**|Query|
|**Action**|**Effect**|
|**Run**|Run the specified ad-hoc query.|

|**Category**|Query Plan|
|**Action**|**Effect**|
|**Get**|List all available query plans, and get specific query plan details.|

Any actions not listed here are currently unused. You may pre-empetively grant entitlements for unused Actions, in case they are used in the future.


## Request Formats
### REST

For non-AUD actions, the REST API supports `GET` requests, with parameters added to the action URL. 

e.g.:

**to get the definition of an existing data source:** `/api/v1/data_source/get/$data_source_name`. 

**To get all data sources, omit the parameter:** `/api/v1/data_source/get`.

For AUD actions, the REST API supports `POST` requests only. Post the request payload to the action URL.

e.g.:

**to run an ad-hoc query:** `POST` to `/api/v1/query/run`.

The `POST` should include the correct payload for the request, without the associated action:

```json
{
        "query": "SELECT d1.* FROM data_source.table d1"
}
```


### WebSocket

The WebSocket API uses the same request format for all actions. JSON request payloads have an `action` field which contains the WebSocket API Action.

Actions to operate on an individual entity are usually singular, while Actions that list or change multiple entities are pluralized. 

e.g.:

**to get the definition of an existing data source:** 

```json
{
   "action": "get_data_source",
   "data_source": "$data_source_name"
}
```

**To get all data sources:**

```json
{
   "action": "get_data_sources"
}
```

This convention is the same for AUD actions.

e.g.:

**to run an ad-hoc query:** 

```json
{
        "action": "run_query",
        "query": "SELECT d1.* FROM data_source.table d1"
}
```

## Response Format

Response Formats between the REST and WebSocket APIs are identical.

### Successful Request

All successful requests made via the API will return a payload wrapped in a `data` field:

```json
{
    "data": {...}
}
```

Most Actions will return a JSON object as the value of `data`. `delete` Actions will return a string, `Deleted`.

The REST API will return an HTTP Response Code of `200` for **ALL** successful requests. 

See the individual action `Response Payload` for the exact format of each successful response. 

### Failed Requests

All failed requests made via the API will return a payload containing `code`, `error`, and `details` fields:

```json
{
    "code": response_code,
    "details": {},
    "error": "Message",

}
```

Where `error` is a generic error message (e.g. "Validation Error"), `details` is an object containing error specific metadata (currently only used for a Validation Error), and `code` is one of the following `Response Code`s:

|**Code**|**Meaning**|
|401|Unauthorized - this could be before (e.g. no SPNEGO credentials), or during (e.g. Missing Entitlements) API request handling|
|400|Validation Error - returned by the AUD endpoints (e.g. submitting an invalid data source configuration)|
|404|Missing API endpoint, or requested entity is not found (e.g. attempting to get a non-existent model definition)|
|500|Internal Server Error - any other error not covered above (e.g. invalid JSON payload, unexpected system error)|

The REST API will also set the code as the actual HTTP Response Code (e.g. a Validation Error from the REST API will return a `400 Bad Request` response).

The WebSocket API returns all responses as text. 

### Handling Validation Errors

The `details` field of the Validation Error response has a specific format:

```json
{
   "code": 400,
   "details": {
      "payload_field": [
         "Error message",
         "Additional error message"
      ],
   },
   "error": "Validation Error"
}	
```

e.g. for an invalid Data Source Add or Update action, where the database name was not provided, and the SPN is in an invalid format, the response would be:

```json
{
   "code": 400,
   "details": {
      "auth": [
         "SPN must be in service/hostname@DOMAIN format"
      ],
      "database": [
         "must be present"
      ]
   },
   "error": "Validation Error"
}	
```

## API Actions 

### Data Source

These Actions require information about the configured platform [Data Source Support](extra_docs/data_sources.md). 

The payload examples in this section use the following variables:

|**Variable**|**Definition**|
|$data_source_name|Name of the data source, used directly in queries (e.g. `SELECT d1.* FROM $data_source_name.table d1`)|
|$data_source_type|Data source type - From [data source configuration](extra_docs/data_sources.md)|
|$data_source_type|Data source version - From [data source configuration](extra_docs/data_sources.md)|
|$database_hostname|`:relational` only - Hostname of the database server|
|$database_name|`:relational` only - Name of the database on the server|
|$kerberos_spn|`:relational` and `:web_api` only - Kerberos SPN of the service (`service/hostname@DOMAIN` format)|
|$file_folder_path|`:file` only - Path to the folder where flat files are located|
|$json_result_path|`:file` and `:web_api` only - JSONPath to result array in the JSON payload (e.g. `$.result[\*]`)|
|$csv_field_separator|`:file` only - Field separator for delimited text files (e.g. `,`)|
|$api_base_url|`:web_api` only - Base URL of the REST API (e.g. `http://localhost:4000/api/v1`|
|$mapping_alias|`web_api` only - Alias for the endpoint mapping, used directly in queries (e.g. `SELECT d1.* FROM $data_source_name.'$mapping_alias' d1`)|
|$api_endpoint_uri|`web_api` only - API URI relative to `$url` (e.g. `/data_source/add`)|

#### Add

|**Description**|
|Add a new data source|

##### Request Payload

The request payload for this action varies depending on the data source class.

<!-- tabs-open -->

### WebSocket

**Relational (class: `:relational`):**

```json
{
    "action": "add_data_source",
    "data_source": "$data_source_name",
    "type": "$data_source_type",
    "version": $data_source_version,
    "hostname": "$database_hostname",
    "database": "$database_name",
    "auth": {
       "type": "kerberos",
       "spn": "$kerberos_spn"
    }
}
```

**Flat Files (class: `:file`):**

This payload varies depending on arguments to the `FileConnector` in the platform configuration.

For `result_type: :json`:

```json
{
    "action": "add_data_source",
    "data_source": "$data_source_name",
    "type": "$data_source_type",
    "version": $data_source_version,
    "path": "$file_folder_path",
    "result_path": "$json_result_path"
}
```

For `result_type: :csv`:

```json
{
    "action": "add_data_source",
    "data_source": "$data_source_name",
    "type": "$data_source_type",
    "version": $data_source_version,
    "path": "$file_folder_path",
    "field_separator": "$csv_field_separator"
}
```

**Web API (class: `:web_api`):**

```json
{
    "action": "add_data_source",
    "data_source": "$data_source_name",
    "type": "$data_source_type",
    "version": $data_source_version,
    "url": "$api_base_url",
    "auth": {
       "type": "kerberos",
       "spn": "$kerberos_spn"
    },
    "endpoint_mappings": {
        "$mapping_alias": {
        "uri": "/$api_endpoint_uri",
        "result_path": "$json_result_path"
        }
    }
}
```

### REST

|**API Action**|**Method**|
|`data_source/add`|`POST`|

**Relational (class: `:relational`):**

```json
{
    "data_source": "$data_source_name",
    "type": "$data_source_type",
    "version": $data_source_version,
    "hostname": "$database_hostname",
    "database": "$database_name",
    "auth": {
       "type": "kerberos",
       "spn": "$kerberos_spn"
    }
}
```

**Flat Files (class: `:file`):**

This payload varies depending on arguments to the `FileConnector` in the platform configuration.

For `result_type: :json`:

```json
{
    "data_source": "$data_source_name",
    "type": "$data_source_type",
    "version": $data_source_version,
    "path": "$file_folder_path",
    "result_path": "$json_result_path"
}
```

For `result_type: :csv`:

```json
{
    "data_source": "$data_source_name",
    "type": "$data_source_type",
    "version": $data_source_version,
    "path": "$file_folder_path",
    "field_separator": "$csv_field_separator"
}
```

**Web API (class: `:web_api`):**

```json
{
    "data_source": "$data_source_name",
    "type": "$data_source_type",
    "version": $data_source_version,
    "url": "$api_base_url",
    "auth": {
       "type": "kerberos",
       "spn": "$kerberos_spn"
    },
    "endpoint_mappings": {
        "$mapping_alias": {
        "uri": "/$api_endpoint_uri",
        "result_path": "$json_result_path"
        }
    }
}
```
<!-- tabs-close -->

##### Response Payload

Returns the data source definition wrapped in a `data` field.

e.g.: for a `:relational` data source:

```json
{
    "data": {
         "data_source": "pg_test",
         "type": "PostgreSQL",
         "version": 15,
         "hostname": "127.0.0.1",
         "database": "test",
         "auth": {
            "spn": "postgres/localhost@EXAMPLE.COM"
         }
      }
}	
```
`:file` data source:

```json
{
    "data": {
         "data_source": "csv_test",
         "type": "CSV",
         "version": 1,
         "path": "/var/tmp/csv_test",
         "field_separator": ";",
         "result_path": "$"
      }
}	
```

`:web_api` data source:

```json
{
    "data": {
         "data_source": "web_api_test",
         "type": "REST",
         "version": 1,
         "url": "http://localhost:80",
         "endpoint_mappings": {
            "test": {
               "uri": "/api/path",
               "result_path": "$.*"
            },
         },
         "auth": {
            "spn": "HTTP/localhost@EXAMPLE.COM"
         }
      }
}	
```

#### Update

|**Description**|
|Update an existing data source|

##### Request Payload

The request payload for this action is the similar to the payload for the Add action, except that `type` and `version` are not supported (i.e. you cannot change an existing data source's connector).

<!-- tabs-open -->

### WebSocket

**Relational (class: `:relational`):**

```json
{
    "action": "update_data_source",
    "data_source": "$data_source_name",
    "hostname": $database_hostname,
    "database": $database_name,
    "auth": {
       "type": "kerberos",
       "spn": "$kerberos_spn"
    }
}
```

**Flat Files (class: `:file`):**

This payload varies depending on arguments to the `FileConnector` in the platform configuration.

For `result_type: :json`:

```json
{
    "action": "update_data_source",
    "data_source": "$data_source_name",
    "path": $file_folder_path,
    "result_path": "$json_result_path"
}
```

For `result_type: :csv`:

```json
{
    "action": "update_data_source",
    "data_source": "$data_source_name",
    "path": $file_folder_path,
    "field_separator": "$csv_field_separator"
}
```

**Web API (class: `:web_api`):**

```json
{
    "action": "update_data_source",
    "data_source": "$data_source_name",
    "url": "$api_base_url",
    "auth": {
       "type": "kerberos",
       "spn": "$kerberos_spn"
    },
    "endpoint_mappings": {
        "$mapping_alias": {
        "uri": "/$api_endpoint_uri",
        "result_path": "$json_result_path"
        }
    }
}
```

### REST

|**API Action**|**Method**|
|`data_source/update`|`POST`|

**Relational (class: `:relational`):**

```json
{
    "data_source": "$data_source_name",
    "hostname": $database_hostname,
    "database": $database_name,
    "auth": {
       "type": "kerberos",
       "spn": "$kerberos_spn"
    }
}
```

**Flat Files (class: `:file`):**

This payload varies depending on arguments to the `FileConnector` in the platform configuration.

For `result_type: :json`:

```json
{
    "data_source": "$data_source_name",
    "path": $file_folder_path,
    "result_path": "$json_result_path"
}
```

For `result_type: :csv`:

```json
{
    "data_source": "$data_source_name",
    "path": $file_folder_path,
    "field_separator": "$csv_field_separator"
}
```

**Web API (class: `:web_api`):**

```json
{
    "data_source": "$data_source_name",
    "url": "$api_base_url",
    "auth": {
       "type": "kerberos",
       "spn": "$kerberos_spn"
    },
    "endpoint_mappings": {
        "$mapping_alias": {
        "uri": "/$api_endpoint_uri",
        "result_path": "$json_result_path"
        }
    }
}
```
<!-- tabs-close -->

##### Response Payload

See Add. 

#### Delete

|**Description**|
|Delete an existing data source|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "delete_data_source",
    "data_source": "$data_source_name"
}
```
### REST

|**API Action**|**Method**|
|`data_source/delete`|`POST`|

```json
{
    "data_source": "$data_source_name"
}
```
<!-- tabs-close -->

##### Response Payload

```json
{
    "data": "Deleted"
}	
```

#### Get

|**Description**|
|Get definition of an existing data source|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "get_data_source",
    "data_source": "$data_source_name"
}
```
### REST

|**API Action**|**Method**|
|`data_source/get/$data_source_name`|`GET`|

<!-- tabs-close -->

##### Response Payload

Returns the Data Source definition wrapped in a `data` field. 

e.g.:

e.g.: for a `:relational` data source:

```json
{
    "data": {
         "data_source": "pg_test",
         "type": "PostgreSQL",
         "version": 15,
         "hostname": "127.0.0.1",
         "database": "test",
         "auth": {
            "spn": "postgres/localhost@EXAMPLE.COM"
         }
      }
}	
```
`:file` data source:

```json
{
    "data": {
         "data_source": "csv_test",
         "type": "CSV",
         "version": 1,
         "path": "/var/tmp/csv_test",
         "field_separator": ";",
         "result_path": "$"
      }
}	
```

`:web_api` data source:

```json
{
    "data": {
         "data_source": "web_api_test",
         "type": "REST",
         "version": 1,
         "url": "http://localhost:80",
         "endpoint_mappings": {
            "test": {
               "uri": "/api/path",
               "result_path": "$.*"
            },
         },
         "auth": {
            "spn": "HTTP/localhost@EXAMPLE.COM"
         }
      }
}	
```

#### Get All

|**Description**|
|List all data sources|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "get_data_sources"
}
```

### REST

|**API Action**|**Method**|
|`data_source/get`|`GET`|

<!-- tabs-close -->

##### Response Payload

`data` is a JSON object mapping each $data_source_name to it's definition.

e.g.:

```json
{
   "data": {
      "csv_test": {
         "data_source": "csv_test",
         "type": "CSV",
         "version": 1,
         "path": "/var/tmp/csv_test",
         "field_separator": ";",
         "result_path": "$"
      },
      "pg_test": {
         "data_source": "pg_test",
         "type": "PostgreSQL",
         "version": 15,
         "hostname": "127.0.0.1",
         "database": "test",
         "auth": {
            "spn": "postgres/localhost@EXAMPLE.COM"
         }
      },
      "web_api_test": {
         "data_source": "web_api_test",
         "type": "REST",
         "version": 1,
         "url": "http://localhost:80",
         "endpoint_mappings": {
            "test": {
               "uri": "/api/path",
               "result_path": "$.*"
            },
         },
         "auth": {
            "spn": "HTTP/localhost@EXAMPLE.COM"
         }
      }
   }
}	
```

### Model

The payload examples in this section use the following variables:

|**Variable**|**Definition**|
|$model_name|Name of the model, used to associate the model with endpoints|
|$query|A valid query to associate with the model, which will be run when any endpoint mapped to this model is executed (e.g. `SELECT d1.* FROM data_source_name.table d1`)|

#### Add

|**Description**|
|Add a new model|

<!-- tabs-open -->

### WebSocket

##### Request Payload

```json
{
    "action": "add_model",
    "model": "$model_name",
    "query": "$query"
}
```

### REST

|**API Action**|**Method**|
|`model/add`|`POST`|

```json
{
    "model": "$model_name",
    "query": "$query"
}
```

<!-- tabs-close -->

##### Response Payload

Returns the Model definition wrapped in a `data` field.

e.g.:

```json
{
   "data": {
      "model": "test_model",
      "query": "SELECT d1.* FROM data_source_name.table d1"
   }
}	
```

#### Update

|**Description**|
|Update an existing model|

##### Request Payload

The request payload for this action is the similar to the payload for the Add action.

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "update_model",
    "model": "$model_name",
    "query": "$query"
}
```

### REST

|**API Action**|**Method**|
|`model/update`|`POST`|

```json
{
    "model": "$model_name",
    "query": "$query"
}
```

<!-- tabs-close -->

##### Response Payload

See Add. 

#### Delete

|**Description**|
|Delete an existing model|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "delete_model",
    "model": "$model_name"
}
```

### REST

|**API Action**|**Method**|
|`model/delete`|`POST`|

```json
{
    "model": "$model_name"
}
```

<!-- tabs-close -->

##### Response Payload

```json
{
    "data": "Deleted"
}	
```

#### Get

|**Description**|
|Get definition of an existing model|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "get_model",
    "model": "$model_name"
}
```

### REST

|**API Action**|**Method**|
|`model/get/$model_name`|`GET`|

<!-- tabs-close -->

##### Response Payload

Returns the Model definition wrapped in a `data` field. 

e.g.:

```json
{
   "data": {
      "model": "test_model",
      "query": "SELECT d1.* FROM data_source_name.table d1"
   }
}	
```

#### Get All

|**Description**|
|List all models|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "get_models"
}
```

### REST

|**API Action**|**Method**|
|`model/get`|`GET`|

<!-- tabs-close -->

##### Response Payload

`data` is a JSON object mapping each $model_name to it's definition.

e.g.:

```json
{
   "data": {
      "test_model": {
         "model": "test_model",
         "query": "SELECT d1.* FROM data_source_name.table d1"
      }
}
```

### Endpoint

The payload examples in this section use the following variables:

|**Variable**|**Definition**|
|$endpoint_name|Name of the endpoint, used to uniquely identify the endpoint in all payloads|
|$model_name|Name of the model to associate with the endpoint, which determines what underlying query is executed|


#### Add

|**Description**|
|Add a new endpoint|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "add_endpoint",
    "endpoint": "$endpoint_name",
    "model": "$model_name"
}
```

### REST

|**API Action**|**Method**|
|`endpoint/add`|`POST`|

```json
{
    "endpoint": "$endpoint_name",
    "model": "$model_name"
}
```

<!-- tabs-close -->

##### Response Payload

Returns the Endpoint definition wrapped in a `data` field.

e.g.:

```json
{
   "data": {
      "endpoint": "test_endpoint",
      "model": "test_model"
   }
}	
```

#### Update

|**Description**|
|Update an existing endpoint|

##### Request Payload

The request payload for this action is the similar to the payload for the Add action.

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "update_endpoint",
    "endpoint": "$endpoint_name",
    "model": "$model_name"
}
```

### REST

|**API Action**|**Method**|
|`endpoint/update`|`POST`|

```json
{
    "endpoint": "$endpoint_name",
    "model": "$model_name"
}
```

<!-- tabs-close -->

##### Response Payload

See Add. 

#### Delete

|**Description**|
|Delete an existing endpoint|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "delete_endpoint",
    "endpoint": "$endpoint_name"
}
```
### REST

|**API Action**|**Method**|
|`endpoint/delete`|`POST`|

```json
{
    "endpoint": "$endpoint_name"
}
```

<!-- tabs-close -->

##### Response Payload

```json
{
    "data": "Deleted"
}	
```

#### Get

|**Description**|
|Get definition of an existing endpoint|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "get_endpoint",
    "endpoint": "$endpoint_name"
}
```
### REST

|**API Action**|**Method**|
|`endpoint/get/$endpoint_name`|`GET`|

<!-- tabs-close -->

##### Response Payload

Returns the Endpoint definition wrapped in a `data` field.

e.g.:

```json
{
   "data": {
      "endpoint": "test_endpoint",
      "model": "test_model"
   }
}	
```

#### Get All

|**Description**|
|List all endpoints|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "get_endpoints"
}
```

### REST

|**API Action**|**Method**|
|`endpoint/get`|`GET`|

<!-- tabs-close -->

##### Response Payload

`data` is a JSON object mapping each $endpoint_name to it's definition.

e.g.:

```json
{
   "data": {
      "test_endpoint": {
         "endpoint": "test_endpoint",
         "model": "test_model"
      }
   }
}	
```

#### Run

|**Description**|
|Run an existing endpoint|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "run_endpoint",
    "endpoint": "$endpoint_name"
}
```
### REST

This REST endpoint supports `GET` and `POST`.

|**API Action**|**Method**|
|`endpoint/run/$endpoint_name`|`GET`|

|**API Action**|**Method**|
|`endpoint/run`|`POST`|

```json
{
    "endpoint": "$endpoint_name"
}
```

<!-- tabs-close -->

##### Response Payload

Returns a `request_id` wrapped in a `data` field.

e.g.:

```json
{
   "data": {
      "request_id": "00000000-0000-0000-0000-000000000000"
   }
}	
```

This request_id is accepted by all API actions that require a `request_id` (e.g. Request -> Poll, Query Plan -> Get).

### ACL

The payload examples in this section use the following variables:

|**Variable**|**Definition**|
|$ident_type|The type of LDAP entity this ACL is for (e.g. `user` or `group`)|
|$ident_id|ID of the LDAP entity (i.e. the `uid` or `group` from LDAP), should NOT contain the Kerberos domain|
|$boolean| `true` or `false`|

#### Update All

|**Description**|
|Update all ACLs for the platform|

##### Request Payload

This action expects a payload that includes all valid ACLs for the platform.

<!-- tabs-open -->

### WebSocket

```json
	{
        "action": "update_all_acls",
        "acls": [
            {
                "ident": {
                    "type": "$ident_type",
                    "subtype": "ldap",
                    "id": "$ident_id"
                    },
                "acl": {
                    "disabled": $boolean,
                    "data_source": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    },
                    "endpoint": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    },
                    "model": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    },
                    "user": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    },
                    "query": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    },
                    "acl": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    }
                }
           }
      ]
   }
```

### REST

|**API Action**|**Method**|
|`acl/update_all`|`POST`|

```json
	{
        "acls": [
            {
                "ident": {
                    "type": "$ident_type",
                    "subtype": "ldap",
                    "id": "$ident_id"
                    },
                "acl": {
                    "disabled": $boolean,
                    "data_source": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    },
                    "endpoint": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    },
                    "model": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    },
                    "user": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    },
                    "query": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    },
                    "acl": {
                        "add": $boolean,
                        "update": $boolean,
                        "delete": $boolean,
                        "get": $boolean,
                        "run": $boolean
                    }
                }
           }
      ]
   }
```

<!-- tabs-close -->

See the [Entitlement Model](#entitlement-model)  section of this documentation for a detailed explanation of the purpose of each section of the payload.

This action allows the addition of new ACLs, but does **NOT** support deletion. 

Any ACL not included in the payload will remain **unchanged**. 

To disable access for a specific LDAP entity, either set all of it's ACL actions to `false`, or set the `disabled` ACL to `true`.

##### Response Payload

See Get All.

#### Get All

|**Description**|
|List all ACLs for the patform|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "get_acls"
}
```

### REST

|**API Action**|**Method**|
|`acl/get`|`GET`|

<!-- tabs-close -->

##### Response Payload

Returns a list of objects representing each ACL definition, wrapped in a `data` field.

e.g:

```json
{
   "data": [
      {
         "ident": {
            "type": "user",
            "subtype": "ldap",
            "id": "test"
         },
         "acls": {
            "disabled": false,
            "data_source": {
               "add": false,
               "update": false,
               "delete": false,
               "get": true,
               "run": false
            },
            "endpoint": {
               "add": false,
               "update": false,
               "delete": false,
               "get": false,
               "run": false
            },
            "model": {
               "add": false,
               "update": false,
               "delete": false,
               "get": false,
               "run": false
            },
            "query": {
               "add": false,
               "update": false,
               "delete": false,
               "get": false,
               "run": false
            },
            "acl": {
               "add": false,
               "update": false,
               "delete": false,
               "get": false,
               "run": false
            },
            "query_plan": {
               "add": false,
               "update": false,
               "delete": false,
               "get": false,
               "run": false
            },
            "request": {
               "add": false,
               "update": false,
               "delete": false,
               "get": false,
               "run": false
            }
         }
      },
      {
         "ident": {
            "type": "group",
            "subtype": "ldap",
            "id": "demo_group"
         },
         "acls": {
            "disabled": false,
            "data_source": {
               "add": true,
               "update": true,
               "delete": true,
               "get": true,
               "run": true
            },
            "endpoint": {
               "add": true,
               "update": true,
               "delete": true,
               "get": true,
               "run": true
            },
            "model": {
               "add": true,
               "update": true,
               "delete": true,
               "get": true,
               "run": true
            },
            "query": {
               "add": true,
               "update": true,
               "delete": true,
               "get": true,
               "run": true
            },
            "acl": {
               "add": true,
               "update": true,
               "delete": true,
               "get": true,
               "run": true
            },
            "query_plan": {
               "add": true,
               "update": true,
               "delete": true,
               "get": true,
               "run": true
            },
            "request": {
               "add": true,
               "update": true,
               "delete": true,
               "get": true,
               "run": true
            }
         }
      }
   ]
}	
```

### Request

The payload examples in this section use the following variables:

|**Variable**|**Definition**|
|$request_id|The Request ID of the request, as returned by Endpoint -> Run or Query -> Run|

Additionally, the Actions in this section only operate on requests executed since the platform was last started. 

#### Get All

|**Description**|
|List all requests (does NOT return the result sets)|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "get_requests"
}
```

### REST

|**API Action**|**Method**|
|`request/get`|`GET`|

<!-- tabs-close -->

##### Response Payload

Returns the metadata for all requests, wrapped in a `data` field, e.g:

```json
{
   "data": {
      "00000000-0000-0000-0000-000000000000": {
         "status": "COMPLETED",
         "start_time": "2024-01-31T23:35:48.063767Z",
         "end_time": "2024-01-31T23:35:48.120823Z",
         "model": "test_model",
         "endpoint": "test_endpoint",
         "query": "SELECT d1.* FROM data_source_name.table d1",
         "username": "test",
         "error": null,
         "expired": false
      }
   }
}	
```

#### Poll

|**Description**|
|Get the status of an existing request|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "poll_request",
    "request_id": "$request_id"
}
```

### REST

|**API Action**|**Method**|
|`request/poll/$request_id`|`GET`|


<!-- tabs-close -->

**IMPORTANT:** This API action does NOT return result sets. For `COMPLETED` requests, `expired` indicates if the result set is still available, or has been purged.

##### Response Payload

Returns the query metadata, and additional information based in the `status` of the request.
e.g.:

```json
{
   "data": {
      "status": "COMPLETED",
      "start_time": "2024-01-31T23:35:48.063767Z",
      "end_time": "2024-01-31T23:35:48.120823Z",
      "model": "test_model",
      "endpoint": "test_endpoint",
      "query": "SELECT d1.* FROM data_source_name.table d1",
      "username": "test",
      "error": null,
      "expired": false
   }
}	
```

For expired requests: `expired` will be set to `true`, along with an error message.

e.g.:

```json
{
   "data": {
      "status": "COMPLETED",
      "start_time": "2024-01-31T23:35:48.063767Z",
      "end_time": "2024-01-31T23:35:48.120823Z",
      "model": "test_model",
      "endpoint": "test_endpoint",
      "query": "SELECT d1.* FROM data_source_name.table d1",
      "username": "test",
      "error": "Result set has expired.",
      "expired": true
   }
}	
```

For `FAILED` requests: will return an error message.

e.g.:

```json
{
   "data": {
      "status": "FAILED",
      "start_time": "2024-01-31T23:45:49.648444Z",
      "end_time": "2024-01-31T23:45:49.648546Z",
      "model": null,
      "endpoint": null,
      "query": "SELECT * FROM invalid",
      "username": "test",
      "error": "query parse error: expected string \" FROM \" (remaining query segment: * FROM invalid)",
      "expired": false
   }
}	
```


#### Result

|**Description**|
|Get the result set for a previously executed request|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "get_result",
    "request_id": "$request_id"
}
```

### REST

|**API Action**|**Method**|
|`request/result/$request_id`|`GET`|


<!-- tabs-close -->

**IMPORTANT:** Result sets are periodically purged from the platform. An expired or unavailable result (e.g. a failed or incomplete request) will return a `404` error response.

##### Response Payload

Returns the query result set, with an ordered list of `columns` that match the nested lists in `rows`. 
e.g.:

```json
{
  "data": {
   "columns": ["col1","col2"],
   "rows": [
["val1.1","val2.1"],
["val1.2","val2.2"],
    ]
  }
}
```

#### Query

The payload examples in this section use the following variables:

|**Variable**|**Definition**|
|$query|A valid query to execute (e.g. `SELECT d1.* FROM data_source_name.table d1`)|

#### Run

|**Description**|
|Run an ad-hoc query|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "run_query",
    "query": "$query"
}
```

### REST

|**API Action**|**Method**|
|`query/run`|`POST`|

```json
{
    "query": "$query"
}
```

<!-- tabs-close -->

##### Response Payload

Returns a `request_id` wrapped in a `data` field.

e.g.:

```json
{
   "data": {
      "request_id": "00000000-0000-0000-0000-000000000000"
   }
}	
```

This request_id is accepted by all API actions that require a `request_id` (e.g. Request -> Poll, Query Plan -> Get).

### Query Plan

The payload examples in this section use the following variables:

|**Variable**|**Definition**|
|$request_id|The Request ID of the request, as returned by Endpoint -> Run or Query -> Run|

Additionally, the Actions in this section only operate on requests executed since the platform was last started. 

#### Get

|**Description**|
|Get the query execution plan for the referenced request.|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "get_query_plan",
    "request_id": "$request_id"
}
```
### REST

|**API Action**|**Method**|
|`query_plan/get/$request_id`|`GET`|

<!-- tabs-close -->

##### Response Payload

Query plan entry fields are defined as follows:

|**Field**|**Definition**|
|start_time|The start time of that stage of processing|
|end_time|The end time of that stage of processing|
|status|The status of that stage of processing, can be used to identify where a query failed|
|indent|The "level" the functionality occurred at, used as a grouping mechanism (e.g. all stages between two entries at the same indent level, are part of that level)|
|duration|The duration, in nanoseconds, of that stage of processing|
|summary|A short description of the stage of processing|
|details|Contains specific details relevant to that segment of processing. For fetch segments, will include the data source information (as a `resource` object with `alias`,`data_source`, and `src` (e.g. table) fields). For entries in "failed" status, will include an `error` field.|

Returns all query plan entries for the request, wrapped in a `data` field. May return an empty list if the query failed pre-processing, or if the platform was restarted.

All non-empty query plans have a top level entry of `type` "select".

e.g.:

```json
{
   "data": [
      {
         "start_time": "2024-01-31T23:55:00.435234Z",
         "end_time": "2024-01-31T23:55:00.491089Z",
         "type": "select",
         "status": "completed",
         "details": {},
         "indent": 1,
         "duration": 55855000,
         "summary": "Virtual model SELECT query"
      },
      {
         "start_time": "2024-01-31T23:55:00.435327Z",
         "end_time": "2024-01-31T23:55:00.435335Z",
         "type": "pre_validate",
         "status": "completed",
         "details": {},
         "indent": 2,
         "duration": 8000,
         "summary": "Initial query validation"
      },
      {
         "start_time": "2024-01-31T23:55:00.435343Z",
         "end_time": "2024-01-31T23:55:00.435579Z",
         "type": "extract_fields",
         "status": "completed",
         "details": {},
         "indent": 2,
         "duration": 236000,
         "summary": "Extract query attributes"
      },
      {
         "start_time": "2024-01-31T23:55:00.435346Z",
         "end_time": "2024-01-31T23:55:00.435399Z",
         "type": "extract_select_fields",
         "status": "completed",
         "details": {},
         "indent": 3,
         "duration": 53000,
         "summary": "...from base SELECT query"
      },
      {
         "start_time": "2024-01-31T23:55:00.489664Z",
         "end_time": "2024-01-31T23:55:00.490011Z",
         "type": "apply_scalar_funcs",
         "status": "completed",
         "details": {},
         "indent": 2,
         "duration": 347000,
         "summary": "Apply scalar platform functions"
      },
      {
         "start_time": "2024-01-31T23:55:00.490376Z",
         "end_time": "2024-01-31T23:55:00.490578Z",
         "type": "apply_aggregate_funcs",
         "status": "completed",
         "details": {},
         "indent": 2,
         "duration": 202000,
         "summary": "Apply aggregate platform functions"
      },
      {
         "start_time": "2024-01-31T23:55:00.435427Z",
         "end_time": "2024-01-31T23:55:00.435468Z",
         "type": "extract_segment_fields",
         "status": "completed",
         "details": {},
         "indent": 3,
         "duration": 41000,
         "summary": "...from query segments"
      },
      {
         "start_time": "2024-01-31T23:55:00.435474Z",
         "end_time": "2024-01-31T23:55:00.435499Z",
         "type": "classify_funcs",
         "status": "completed",
         "details": {},
         "indent": 3,
         "duration": 25000,
         "summary": "Classify platform functions"
      },
      {
         "start_time": "2024-01-31T23:55:00.435504Z",
         "end_time": "2024-01-31T23:55:00.435527Z",
         "type": "validate_group_by",
         "status": "completed",
         "details": {},
         "indent": 3,
         "duration": 23000,
         "summary": "Validate GROUP criteria"
      },
      {
         "start_time": "2024-01-31T23:55:00.435530Z",
         "end_time": "2024-01-31T23:55:00.435575Z",
         "type": "extract_func_fields",
         "status": "completed",
         "details": {},
         "indent": 3,
         "duration": 45000,
         "summary": "...from function calls"
      },
      {
         "start_time": "2024-01-31T23:55:00.435647Z",
         "end_time": "2024-01-31T23:55:00.435757Z",
         "type": "prepare_segments",
         "status": "completed",
         "details": {},
         "indent": 2,
         "duration": 110000,
         "summary": "Pre-process query segments"
      },
      {
         "start_time": "2024-01-31T23:55:00.435761Z",
         "end_time": "2024-01-31T23:55:00.484054Z",
         "type": "get_segment_streams",
         "status": "completed",
         "details": {},
         "indent": 2,
         "duration": 48293000,
         "summary": "Fetch data from data source(s)"
      },
      {
         "start_time": "2024-01-31T23:55:00.489300Z",
         "end_time": "2024-01-31T23:55:00.489611Z",
         "type": "filter_result",
         "status": "completed",
         "details": {},
         "indent": 2,
         "duration": 311000,
         "summary": "Filter result set"
      },
      {
         "start_time": "2024-01-31T23:55:00.490019Z",
         "end_time": "2024-01-31T23:55:00.490051Z",
         "type": "group_result",
         "status": "completed",
         "details": {},
         "indent": 2,
         "duration": 32000,
         "summary": "GROUP result set"
      },
      {
         "start_time": "2024-01-31T23:55:00.490586Z",
         "end_time": "2024-01-31T23:55:00.490612Z",
         "type": "order_result",
         "status": "completed",
         "details": {},
         "indent": 2,
         "duration": 26000,
         "summary": "ORDER result set"
      },
      {
         "start_time": "2024-01-31T23:55:00.490699Z",
         "end_time": "2024-01-31T23:55:00.491078Z",
         "type": "finalize_result",
         "status": "completed",
         "details": {},
         "indent": 2,
         "duration": 379000,
         "summary": "Finalize and cleanup result set"
      },
      {
         "start_time": "2024-01-31T23:55:00.435764Z",
         "end_time": "2024-01-31T23:55:00.476545Z",
         "type": "segment_stream",
         "status": "completed",
         "details": {
            "resource": {
               "alias": "ref2",
               "data_source": "pg_test",
               "src": "group_by_test"
            }
         },
         "indent": 3,
         "duration": 40781000,
         "summary": "...fetch from data source..."
      },
      {
         "start_time": "2024-01-31T23:55:00.476579Z",
         "end_time": "2024-01-31T23:55:00.483447Z",
         "type": "segment_stream",
         "status": "completed",
         "details": {
            "resource": {
               "alias": "ref1",
               "data_source": "mdb_test",
               "src": "table_test"
            }
         },
         "indent": 3,
         "duration": 6868000,
         "summary": "...fetch from data source..."
      },
      {
         "start_time": "2024-01-31T23:55:00.484552Z",
         "end_time": "2024-01-31T23:55:00.489235Z",
         "type": "process_joins",
         "status": "completed",
         "details": {},
         "indent": 2,
         "duration": 4683000,
         "summary": "Process JOIN segments"
      },
      {
         "start_time": "2024-01-31T23:55:00.484563Z",
         "end_time": "2024-01-31T23:55:00.488909Z",
         "type": "process_join",
         "status": "completed",
         "details": {},
         "indent": {
            "join_type": "LEFT",
            "resources": [
               {
                  "data_source": "pg_test",
                  "src": "group_by_test",
                  "alias": "ref2"
               },
               {
                  "data_source": "mdb_test",
                  "src": "table_test",
                  "alias": "ref1"
               }
            ]
         },
         "duration": 4346000,
         "summary": "...process join"
      }
   ]
```

A failed entry would contain an `error`, e.g.:

```json
{
         "start_time": "2024-01-31T23:54:37.834647Z",
         "end_time": "2024-01-31T23:54:37.941841Z",
         "type": "segment_stream",
         "status": "failed",
         "details": {
            "error": "Error Message",
            "resource": {
               "alias": "d1",
               "data_source": "data_source_name",
               "src": "table"
            }
         },
         "indent": 3,
         "duration": 107194000,
         "summary": "...fetch from data source..."
      }
```



#### Get All

|**Description**|
|Get all "select" entries from all query plans (i.e. a high-level listing of all existing query plans).|

##### Request Payload

<!-- tabs-open -->

### WebSocket

```json
{
    "action": "get_query_plans"
}
```

### REST

|**API Action**|**Method**|
|`query_plan/get`|`GET`|

<!-- tabs-close -->

##### Response Payload

`data` is a JSON object mapping each $request_id to it's top level "select" entry. All fields are the same as in the Get action.

e.g:


```json
{
   "data": {
        "00000000-0000-0000-0000-000000000000": {
            "start_time": "2024-01-31T23:35:48.064271Z",
            "end_time": "2024-01-31T23:35:48.120689Z",
            "type": "select",
            "status": "completed",
            "details": {},
            "indent": 1,
            "duration": 56418000,
            "summary": "Virtual model SELECT query"
        }
}
```


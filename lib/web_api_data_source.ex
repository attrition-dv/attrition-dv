#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule WebAPIDataSource do
  @moduledoc """
  Represents a Web API Data Source in the `Metadata` repository.

  Definitions:

  * `:data_source`: The Data Source name in submitted casing (i.e. not lowercased)
  * `:type`: Data Source type as defined in the platform configuration (e.g. REST)
  * `:version`: Not currently used for Web APIs.
  * `:url`: Web API base URL.
  * `:endpoint_mappings`: Map of friendly names to API endpoint URIs with result path details (e.g. `"endpoint": {
          "uri": "/path/to/endpoint",
          "result_path": "$.result[*]"
       }`)
  * `:auth`: Authentication parameters for the API. Currently always a map containing a Kerberos SPN.
  * `:_class`: Always `:web_api` (INTERNAL only)

  """
    @enforce_keys [:data_source,:type,:version,:url,:auth,:endpoint_mappings]
    @derive {Jason.Encoder,only: [:data_source,:type,:version,:url,:endpoint_mappings,:auth]}
    defstruct [:data_source,:type,:version,:url,:auth,:endpoint_mappings,_class: :web_api]
end
defmodule WebAPIEndpointMapping do
  @moduledoc """
  Represents a Web API endpoint mapping. Used as a child of `WebAPIDataSource` for `WebAPIDataSource.endpoint_mappings`.

  Definitions:

  * `:uri`: API endpoint URI (e.g. /path/to/endpoint")
  * `:result_path`: JSONPath to result data (e.g. "$.result[*]")

  """
    @enforce_keys [:uri,:result_path]
    @derive {Jason.Encoder,only: [:uri,:result_path]}
    defstruct [:uri,:result_path]
end

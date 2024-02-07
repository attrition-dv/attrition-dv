#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QueryComponentResource do
  @moduledoc """
  Represents a resource (e.g. database table, flat-file, Web API endpoint) in an SQL query.

  Used in `Parsec` for `SELECT` (e.g. SELECT * FROM resource) and JOIN (e.g. LEFT JOIN resource) operations.

  In a query, a resource is typically in the form of `data_source.src [alias]`.

  Definitions:

  * `:data_source`: The data source name where the resource is located (as defined in a `Metadata` entry).
  * `:src`: The requested resource (e.g. table name, flat-file basename, mapped Web API endpoint name).
  * `:alias`: The alias provided in the query. Used for referencing fields of that resource elsewhere in the query.
  """
  @derive {Jason.Encoder,only: [:data_source,:src,:alias]} # Needed for `QP`
  defstruct [:data_source,:src,:alias]
end

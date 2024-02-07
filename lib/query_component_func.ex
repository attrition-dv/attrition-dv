#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QueryComponentFunc do
  @moduledoc """
  Represents a function in an SQL query (e.g. `LOWER(...)`)

  Used in `Parsec`.

  Definitions:

  * `:src`: The targeted data source, set during processing, and only on local functions (operating on a single data source).
  * `:type`: The function type (based on `Parsec`: may be set to `:scalar_vararg`, `:aggregate`, or `nil` (scalar))
  * `:name`: The atomized string name of the function (e.g. `:lower`).
  * `:params`: The specified function parameters as a list of structs (may include `QueryComponentFuncField`,`QueryComponentAllFields`,`QueryComponentAliasPlaceholder`, and `QueryComponentQuotedString`).
  * `:alias`: The function alias (e.g. `SELECT LOWER(alias.field) AS function_alias`).
  * `:_func`: Function to use to generate data source query fragment (`_platform: false` only) (INTERNAL only).
  * `:_ident`: Identifer to disambiguate function calls even if not aliased, currently takes the form of "{atomized_function_name_:_index}" (e.g. lower_1) (INTERNAL only).
  * `:_index`: Position of the function in the result set (INTERNAL only).
  * `:_drop`: Whether to remove the function before returning the result set, currently unused (INTERNAL only).
  * `:_applied`: Whether the function was already applied (processed) during query processing (INTERNAL only).
  * `:_platform`: Whether the function should be executed at the platform level (instead of the data source level) (INTERNAL only).
  """
  defstruct [:src,:type,:name,:params,:alias,:_index,:_func,:_ident,_applied: false,_drop: false,_platform: false]
end

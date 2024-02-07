#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QueryComponentQuotedString do
  @moduledoc """
  Represents a quoted string literal in an SQL query (e.g. `CONCAT_WS(',',...)`)

  Used in `Parsec`.

  Definitions:

  * `:field`: The raw quoted string literal (e.g. ',')
  * `:unquoted`: `:field` with the quotes removed (e.g. ,)
   * `:alias`: The function alias (e.g. `SELECT LOWER(alias.field) AS function_alias`), currently unused.
  * `:_index`: Position of the function in the result set, currently unused (INTERNAL only).
  * `:_drop`: Whether to remove the function before returning the result set, currently unused (INTERNAL only)
  * `:_applied`: Whether the function was already applied (processed) during query processing, currently unused (INTERNAL only)
  * `:_platform`: Whether the function should be executed at the platform level (instead of the data source level), currently unused (INTERNAL only)
  """
  defstruct [:field,:unquoted,:alias,:_index,_drop: false,_applied: false]
end
defimpl String.Chars,for: QueryComponentQuotedString do
  def to_string(param) do
    param.field
  end
end

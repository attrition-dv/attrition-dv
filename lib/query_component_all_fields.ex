#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QueryComponentAllFields do
  @moduledoc """
  Represents "*" in an SQL query (e.g. `SELECT *`, `COUNT(*)`)

  Used in `Parsec` for parsing function calls and `SELECT` statements.

  Definitions:

  * `:src`: The targeted data source.
  * `:_index`: Position of the fields in the result set (INTERNAL only).
  * `:_drop`: Whether to remove the fields before returning the result set, used for unrequested fields only retrieved for interim processing (INTERNAL only).
  * `:_applied`: Whether the fields were already applied (processed) during query processing (INTERNAL only).
  """
  defstruct [:src,:_index,_drop: false,_applied: false]
end
defimpl String.Chars,for: QueryComponentAllFields do
  def to_string(_param) do
    "*"
  end
end

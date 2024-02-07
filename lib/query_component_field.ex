#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QueryComponentField do
  @moduledoc """
  Represents a field in an SQL query (e.g. `alias.field`)

  Used in `Parsec`.

  Definitions:

  * `:src`: The targeted data source.
  * `:field`: The field name.
  * `:alias`: The field alias (e.g. `SELECT alias.field AS field_alias`).
  * `:_index`: Position of the field in the result set (INTERNAL only).
  * `:_drop`: Whether to remove the field before returning the result set, used for unrequested fields only retrieved for interim processing (INTERNAL only).
  * `:_applied`: Whether the field was already applied (processed) during query processing (INTERNAL only).
  """
  defstruct [:src,:field,:alias,:_index,_applied: false,_drop: false]
end

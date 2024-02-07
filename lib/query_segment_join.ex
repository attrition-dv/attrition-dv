#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QuerySegmentJOIN do
  @moduledoc """
  Represents a `JOIN` clause in an SQL query (e.g. `LEFT JOIN ds_alias.src alias ON(...)`).

  Used in `Parsec` for processing `LEFT JOIN`, `RIGHT JOIN` and `INNER JOIN`.

  Definitions:

  * `:type`: The type of JOIN clause (`:LEFT`,`:RIGHT`,`:INNER`)
  * `:resource`: The `QueryComponentResource` being JOINed.
  * `:clauses`: List of clauses applied in the JOIN. Currently, only supports a single `QueryComponentBinaryClause`.
  """
  defstruct [:type,:resource,:alias,:clauses]
end

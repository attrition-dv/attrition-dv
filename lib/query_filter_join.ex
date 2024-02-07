#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QueryFilterJoin do
  @moduledoc """
  Represents the filter form of a `JOIN` clause.

  Used in `QueryEngine` for processing `QueryComponentJOIN` operations.

  Definitions:

  * `:type`: The type of JOIN clause (`:LEFT`,`:RIGHT`,`:INNER`)
  * `:clauses`: List of clauses applied in the JOIN. Currently, only supports a single `QueryComponentBinaryClause`.
  """
  defstruct [:type,:clauses]
end

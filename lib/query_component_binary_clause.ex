#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QueryComponentBinaryClause do
  @moduledoc """
  Represents a binary comparison clause in an SQL query. A binary comparison clause is one with two operands (e.g. `alias.field1 = alias2.field1`)

  Used in `Parsec` for parsing `JOIN` and `WHERE` clause conditions.

  Definitions:

  * `:p1`: The first field being compared (e.g. `alias.field`)
  * `:operator`: The atomized literal of the comparison operator (e.g. `:equals`)
  * `:p2`: The second field being compared (e.g. `alias.field2`)
  """
  defstruct [:p1,:operator,:p2]
end

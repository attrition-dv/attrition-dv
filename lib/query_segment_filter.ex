#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QuerySegmentFilter do
  @moduledoc """
  Represents a filter clause in an SQL query.

  Used in `Parsec` for processing `WHERE` clauses.

  Definitions:

  * `:type`: The type of filter clause, currently always `:WHERE`.
  * `:clauses`: List of clauses applied in the filter. Currently, only supports a single `QueryComponentBinaryClause`.
  """
  defstruct [:type,:clauses]
end

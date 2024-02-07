#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QuerySegmentSELECT do
  @moduledoc """
  Represents a `SELECT` clause in an SQL query (e.g. `SELECT alias.field AS field_alias FROM data_source.src alias`)

  Used in `Parsec` for the initial `SELECT` query only. Does not include `JOIN`s, `ORDER BY`, etc.

  Definitions:

  * `:fields`: The query fields being SELECTed. This is the full list for the entire query, regardless of `:resource`. May be any valid field type (e.g.`QueryComponentField`,`QueryComponentFunc`)
  * `:resource`: The `QueryComponentResource` referenced in the `FROM` portion of the select query.
  """
  defstruct [:fields,:resource]
end

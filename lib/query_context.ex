#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QueryContext do
  @moduledoc """
  Represents the context of an in progress query.

  Definitions:

  * `:request_id`: Request ID of the query (as generated in `DV`).
  * `:model`: The name of the executed model (`run_endpoint` only).
  * `:endpoint`: The name of the executed endpoint (`run_endpoint` only).
  * `:username`: The name of the requesting user.
  """
  defstruct [:request_id,:model,:endpoint,:username]
end

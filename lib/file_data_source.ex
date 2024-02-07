#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule FileDataSource do
  @moduledoc """
  Represents a flat-file Data Source in the `Metadata` repository.

  Definitions:

  * `:data_source`: The Data Source name in submitted casing (i.e. not lowercased)
  * `:type`: Data Source type as defined in the platform configuration (e.g. CSV, JSON)
  * `:version`: Not currently used for flat-files.
  * `:path`: Path to the flat-files.
  * `:field_separator`: Delimiter for flat-file columns (e.g. ",") (when `:type` is defined with `result_type: :csv`)
  * `:result_path`: JSONPath to result data (e.g. "$.result[*]") (when `:type` is defined with `result_type: :json`)
  * `:_class`: Always `:file` (INTERNAL only)

  """
  @enforce_keys [:data_source,:type,:version,:path]
  @derive {Jason.Encoder,only: [:data_source,:type,:version,:path,:field_separator,:result_path]}
  defstruct [:data_source,:type,:version,:path,:field_separator,:result_path,_class: :file]
  end

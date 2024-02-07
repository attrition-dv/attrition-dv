#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule ODBCDataSource do
  @moduledoc """
  Represents an ODBC Data Source in the `Metadata` repository.

  Definitions:

  * `:data_source`: The Data Source name in submitted casing (i.e. not lowercased)
  * `:type`: Data Source type as defined in platform configuration (e.g. PostgreSQL, MariaDB)
  * `:version`: Database version the modules are based on
  * `:hostname`: Database server hostname
  * `:database`: Database name
  * `:auth`: Authentication parameters for the database. Currently always `DataSourceKerberosAuth`.
  * `:_class`: Always `:relational` (INTERNAL only)

  """
@enforce_keys [:data_source,:type,:version,:hostname,:database,:auth]
@derive {Jason.Encoder,only: [:data_source,:type,:version,:hostname,:database,:auth]}
defstruct [:data_source,:type,:version,:hostname,:database,:auth,_class: :relational]
end

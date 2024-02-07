#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule Metadata.Backend do
  @moduledoc """
  Default `Metadata` backend. Wraps calls to `CubDB`.
  """
  @doc """
  Insert/Update a `key`:`value` pair into the specified CubDB `table`.
  """
  def put(table,key,value) do
    CubDB.put(table,key,value)
  end
  @doc """
  Insert/Update multiple `key`:`value` pairs into the specified CubDB `table`.

  Expects a list of tuples (e.g. `[{key,val}]`).
  """
  def put_multi(table,tuples) do
    CubDB.put_multi(table,tuples)
  end
  @doc """
  Get the value for `key` from the specified CubDB `table`.
  """
  def get(table,key) do
    CubDB.fetch(table,key)
  end
  @doc """
  Delete the value for `key` from the specified CubDB `table`.
  """
  def delete(table,key) do
    CubDB.delete(table,key)
  end
  @doc """
  Delete ALL values from the specified CubDB `table`. Only used for `mix test`.
  """
  def delete_all(table) do
    CubDB.clear(table)
    CubDB.file_sync(table)
  end
  @doc """
  Get all key:value pairs from the specified CubDB `table`.
  """
  def get_all(table) do #,min_key,max_key) do
    CubDB.select(table)
  end
  @doc """
  Returns the number of entries in the specified CubDB `table`.
  """
  def size(table) do
    CubDB.size(table)
  end
end
defmodule Metadata do
  @moduledoc """
  Metadata repository access for the platform.

  Used for mediating all required platform metadata requests.

  Wraps `Metadata.Backend`.
  """

  @doc """
  Insert/Update a `key`:`value` pair for the specified repository `table`.
  """
  def add(table,key,value) do
    Metadata.Backend.put(table,key,value)
  end
  @doc """
  Insert/Update a `key`:`value` pair for the specified repository `table`. Wraps `add/3`.
  """
  def update(table,key,value) do
    add(table,key,value)
  end
  @doc """
  Insert/Update multiple `key`:`value` pairs for the specified repository `table`.

  Expects a list of tuples (e.g. `[{key,val}]`).
  """
  def update_multi(table,tuples) do
    Metadata.Backend.put_multi(table,tuples)
  end
  @doc """
  Get the value for `key` from the specified CubDB `table`.

  Returns an error if key is not found.
  """
  def get(table,key) do
    case Metadata.Backend.get(table,key) do
      :error -> {:error,"Key #{inspect key} not found!"}
      value -> value
    end
  end
  @doc """
  Get the value for `key` from the specified CubDB `table`, or the provided `default` value.

  Wraps `get/2`.
  """
  def get_or_default(table,key,default \\ nil) do
    {:ok,case Metadata.Backend.get(table,key) do
      :error -> default
      {:ok,value} -> value
    end}
  end
  @doc """
  Delete the value for `key` from the specified repository `table`.
  """
  def delete(table,key) do
    Metadata.Backend.delete(table,key)
  end
  @doc """
  Delete ALL values from the specified repository `table`. Only used for `mix test`.
  """
  def delete_all(table) do
    Metadata.Backend.delete_all(table)
  end
  @doc """
  Get all key:value pairs from the specified repository `table`.
  """
  def get_all(table) do
    Metadata.Backend.get_all(table)
  end
  @doc """
  Returns the number of entries in the specified repository `table`.
  """
  def size(table) do
    Metadata.Backend.size(table)
  end
end

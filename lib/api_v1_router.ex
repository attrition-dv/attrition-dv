#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule APIV1Router do
  @moduledoc """
  `Plug.Router` for V1 API.

  Directs requests as follows:
    * */client/open_websocket* - `APIV1SocketHandler` (WebSocket)
    * *Any other request* - `APIV1RESTHandler` (REST)

  Supports JSON payloads only. Returns JSON.

  *Part of V1 API*
  """
use Plug.Router
plug :match
plug :dispatch
  # WebSocket clients need to use e.g. /api/v1/client/open_websocket
  # This is future proofing for potential other kinds of API clients
  get "/client/open_websocket" do
    LogUtil.debug("Called open_websocket")
    WebSockAdapter.upgrade(conn,APIV1SocketHandler,%{username: conn.assigns[:username]},timeout: :infinity)
    |> halt()
  end
  # Other /api/v1 calls go to the REST handler, since websocket only uses one endpoint
  forward "/",to: APIV1RESTHandler,init_opts: []
end

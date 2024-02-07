#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule WebBrokerPlug do
  @moduledoc """
  `Plug.Router` for API connections.

  * Performs user authentication (SPNEGO, Kerberos)
  * Delegates to other plugs for API functionality

  """
  use Plug.Router
  plug CORSPlug
  def init(options) do
    options
  end
  plug :auth
  defp auth(conn,opts) do
    do_auth(conn,opts)
  end
  # Initial SPNEGO handshake
  # Uses `:kerlberos` to authenticate the user against `:kerberos_server_keytab`.
  # Based on the logic outlined in https://datatracker.ietf.org/doc/html/rfc4559
  defp accept_result_to_conn(conn,accept_result)
  defp accept_result_to_conn(conn,{:ok,state}) do
    LogUtil.log("SPNEGO OK w/o token")
    conn
    |> Plug.Conn.assign(:username,LogUtil.inspect(user_from_krb(state),label: "SPNEGO Authentication successful for user",level: :info))
  end
  defp accept_result_to_conn(conn,{:ok,token,state}) do
    LogUtil.log("SPNEGO OK w/ token")
    token = Base.encode64(token)
    enc_resp = "Negotiate #{token}"
    conn |> Plug.Conn.put_resp_header("www-authenticate",enc_resp)
    |> Plug.Conn.assign(:username,LogUtil.inspect(user_from_krb(state),label: "SPNEGO Authentication successful for user",level: :info))
  end
  defp accept_result_to_conn(conn,{:continue,token,_state}) do
    LogUtil.log("SPNEGO CONTINUE")
    token = Base.encode64(token)
    enc_resp = "Negotiate #{token}"
    conn |> Plug.Conn.put_resp_header("www-authenticate",enc_resp)
    |> Plug.Conn.put_resp_content_type("text/html")
    |> send_resp(401,"Unauthorized")
    |> halt()
  end
  defp accept_result_to_conn(conn,_accept_result) do
    LogUtil.log("SPNEGO ERROR")
    LogUtil.info("SPNEGO Authentication failed!")
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> send_resp(401,"Unauthorized")
    |> halt()
  end
  defp do_auth(conn,_opts) do
    LogUtil.log("START do_auth()")
    with {:ok,ktd} <- :file.read_file(Application.fetch_env!(:DV,:kerberos_server_keytab)) do
      with {:ok,keytab} <- :krb_mit_keytab.parse(ktd) do
        with [auth_header] <- Plug.Conn.get_req_header(conn,"authorization") do
          LogUtil.log("Handling authorization header...")
          header_parts = String.split(auth_header," ",parts: 2)
          negotiate_token = Enum.at(header_parts,1,"")
          bin_header = Base.decode64!(negotiate_token)
          accept_result = :gss_spnego.accept(bin_header,%{:keytab => keytab,:chan_bindings => <<0::128>>,:sequence => false,:delegate => false,:mutual_auth => true,:replay_detect => true})
          accept_result_to_conn(conn,accept_result)
        else
        _ ->
          LogUtil.log("No auth header!")
          conn |> Plug.Conn.put_resp_header("www-authenticate", "Negotiate")
          |> Plug.Conn.put_resp_content_type("text/html")
          |> send_resp(401,"Unauthorized")
          |> halt()
        end |> LogUtil.pipe("END do_auth()")
      else
        {:error,reason} ->
          LogUtil.error("Error parsing Server Keytab file: #{inspect reason}")
          conn |> Plug.Conn.put_resp_content_type("text/html")
          |> send_resp(500,"Internal Server Error")
          |> halt()
      end
    else
      {:error,:enoent} ->
        LogUtil.error("Server Keytab file does not exist!")
        conn |> Plug.Conn.put_resp_content_type("text/html")
        |> send_resp(500,"Internal Server Error")
        |> halt()
      {:error,reason} ->
        LogUtil.error("Error reading Server Keytab file: #{inspect reason}")
        conn |> Plug.Conn.put_resp_content_type("text/html")
        |> send_resp(500,"Internal Server Error")
        |> halt()
    end
  end
  # For successful SPNEGO authentication extracts username from the returned Kerberos principal
  # Downcases username, and ignores the realm
  defp user_from_krb(state) do
    {:ok,{_krbrealm,{:PrincipalName,_princtype,[krbprinc]}}} = LogUtil.inspect(:gss_spnego.peer_name(state),label: "Kerb peer name")
    String.downcase(to_string(krbprinc))
  end
  plug :match
  plug :dispatch
  forward "/api/v1",to: APIV1Router,init_opts: []
end

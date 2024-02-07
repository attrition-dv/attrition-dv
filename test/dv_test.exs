#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule DVTest do
  @moduledoc """
  Automated test cases for the application.

  Basic end-to-end testing of platform functionality.

  See config in `config/test.exs` for overrides specific to the test environment.

  These tests MUST run synchronously and serially, as they rely on side-effects.
  """

  use ExUnit.Case,async: false
  @moduletag capture_log: true
  import Mock

  # Clear Metadata in case we're re-using the repository path
  # Prep temp dir for later use
  setup_all do
    Enum.each([:dv_data_sources,:dv_models,:dv_endpoints],fn table -> Metadata.delete_all(table) end)
    Temp.track!()
    {:ok,[{:tmp_dir,Temp.mkdir!("dv_test")}]} # Using `Temp` to keep a consistent temp_dir for all of the below tests
  end

  # Mocking is required to avoid attempts to connect to LDAP during testing
  setup_with_mocks [
    {LDAP,[],[
      get_user: fn(_user) ->
        {:ok,%{"memberOf" =>  ["cn=test_group"]}}
      end
    ]}
  ] do
    {:ok,[]}
  end

  # TEST Parsec
  test "Parsec.sql - valid" do
    assert {:ok,_,_,_,_,_} = Parsec.sql("SELECT alias.usename AS username,COUNT(alias2.message) AS msg_count FROM test.test_table alias LEFT JOIN test.test_table2 alias2 ON (alias.usename = alias2.username) GROUP BY alias.usename ORDER BY msg_count DESC LIMIT 1")
  end
  test "Parsec.sql - valid - quoted source" do
    assert {:ok,_,_,_,_,_} = Parsec.sql("SELECT alias.usename AS username,COUNT(alias2.message) AS msg_count FROM test.test_table alias LEFT JOIN test.'test_table2' alias2 ON (alias.usename = alias2.username) GROUP BY alias.usename ORDER BY msg_count DESC LIMIT 1")
  end
  test "Parsec.sql - valid - quoted function param" do
    assert {:ok,_,_,_,_,_} = Parsec.sql("SELECT alias.usename AS username,CONCAT_WS(',',alias2.message) AS messages FROM test.test_table alias LEFT JOIN test.test_table2 alias2 ON (alias.usename = alias2.username)")
  end
  test "Parsec.sql - invalid" do
    assert {:error,_,_,_,_,_} = Parsec.sql("SELECT alias.usename AS username,COUNT(alias2.message) AS msg_count FROM test.test_table alias LEFT JOIN test.test_table2 alias2 ON (alias.usename = alias2.username) GROUP BY alias.usename ORDER BY msg_count DESC HAVING alias.invalid = 'test' LIMIT 1")
  end

  # TEST APIV1 - data_source
  test "APIV1.handle {:data_source,:add} - valid" do
    payload = %{
      "action" => "add_data_source",
      "data_source" => "test_valid_data_source",
      "type" => "REST",
      "version" => 1,
      "url" => "http://localhost:80",
      "auth" => %{
        "type" => "kerberos",
        "spn" => "HTTP/localhost@EXAMPLE.COM"
      },
      "endpoint_mappings" => %{
        "test" => %{
          "uri" => "/cgi-bin/user.pl?variant=3",
          "result_path" => "$.result[*]"
        }
      }
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:data_source,:add} - duplicate" do
    payload = %{
      "action" => "add_data_source",
      "data_source" => "test_valid_data_source",
      "type" => "REST",
      "version" => 1,
      "url" => "http://localhost:80",
      "auth" => %{
        "type" => "kerberos",
        "spn" => "HTTP/localhost@EXAMPLE.COM"
      },
      "endpoint_mappings" => %{
        "test" => %{
          "uri" => "/cgi-bin/user.pl?variant=3",
          "result_path" => "$.result[*]"
        }
      }
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:data_source,:add} - invalid" do
    payload = %{
      "action" => "add_data_source",
      "data_source" => "test_invalid_data_source",
      "type" => "REST",
      "version" => 1,
      "url" => "http://localhost:80",
      "auth" => %{
        "type" => "kerberos",
        "spn" => "HTTP/AMPLE.COM"
      },
      "endpoint_mappings" => %{
        "test" => %{
          "uri" => "/cgi-bin/user.pl?variant=3",
          "result_path" => ""
        }
      }
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:data_source,:update} - valid" do
    payload = %{
      "action" => "update_data_source",
      "data_source" => "test_valid_data_source",
      "url" => "http://localhost:80",
      "auth" => %{
        "type" => "kerberos",
        "spn" => "HTTP/localhost@EXAMPLE2.COM"
      },
      "endpoint_mappings" => %{
        "test" => %{
          "uri" => "/cgi-bin/user.pl?variant=3",
          "result_path" => "$.result[*]"
        },
        "test2" => %{
          "uri" => "/cgi-bin/user2.pl?variant=3",
          "result_path" => "$.result[*]"
        }
      }
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:data_source,:update} - confirm update" do
    case_result = case DV.get_data_source("test_valid_data_source") do
      {:ok,defs} ->
        defs.auth.spn == "HTTP/localhost@EXAMPLE2.COM" and Map.has_key?(defs.endpoint_mappings,"test2")
      _ -> false
    end
    assert case_result,"update to data_source failed!"
  end
  test "APIV1.handle {:data_source,:get}" do
    payload = %{
      "action" => "get_data_source",
      "data_source" => "test_valid_data_source"
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:data_source,:update} - missing" do
    payload = %{
      "action" => "update_data_source",
      "data_source" => "test_missing_data_source",
      "url" => "http://localhost:80",
      "auth" => %{
        "type" => "kerberos",
        "spn" => "HTTP/localhost@EXAMPLE2.COM"
      },
      "endpoint_mappings" => %{
        "test" => %{
          "uri" => "/cgi-bin/user.pl?variant=3",
          "result_path" => "$.result[*]"
        },
        "test2" => %{
          "uri" => "/cgi-bin/user2.pl?variant=3",
          "result_path" => "$.result[*]"
        }
      }
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:data_source,:update} - invalid" do
    payload = %{
      "action" => "update_data_source",
      "data_source" => "test_valid_data_source",
      "version" => 1,
      "url" => "http://localhost:80",
      "auth" => %{
        "type" => "kerberos",
        "spn" => "HTTP/AMPLE.COM"
      },
      "endpoint_mappings" => %{
        "test" => %{
          "uri" => "/cgi-bin/user.pl?variant=3",
          "result_path" => ""
        }
      }
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end

  # TEST APIV1 - model
  test "APIV1.handle {:model,:add} - valid" do
    payload = %{
      "action" => "add_model",
      "model" => "test_valid_model",
      "query" => "SELECT alias.usename AS username,COUNT(alias2.message) AS msg_count FROM test_valid_data_source.'test_endpoint' alias LEFT JOIN test_valid_data_source.test_table2 alias2 ON (alias.usename = alias2.username) GROUP BY alias.usename ORDER BY msg_count DESC LIMIT 1"
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:model,:add} - valid (need two for testing endpoint)" do
    payload = %{
      "action" => "add_model",
      "model" => "test_valid_model_2",
      "query" => "SELECT alias.usename AS username,COUNT(alias2.message) AS msg_count FROM test_valid_data_source.'test_endpoint' alias LEFT JOIN test_valid_data_source.test_table2 alias2 ON (alias.usename = alias2.username) GROUP BY alias.usename ORDER BY msg_count DESC LIMIT 1"
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:model,:add} - duplicate" do
    payload = %{
      "action" => "add_model",
      "model" => "test_valid_model",
      "query" => "SELECT alias.usename AS username,COUNT(alias2.message) AS msg_count FROM test_valid_data_source.'test_endpoint' alias LEFT JOIN test_valid_data_source.test_table2 alias2 ON (alias.usename = alias2.username) GROUP BY alias.usename ORDER BY msg_count DESC LIMIT 1"
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:model,:add} - invalid" do
    payload = %{
      "action" => "add_model",
      "model" => "test_invalid_model",
      "query" => "SELEC"
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:model,:update} - valid" do
    payload = %{
      "action" => "update_model",
      "model" => "test_valid_model",
      "query" => "SELECT alias.usename AS username,COUNT(alias2.message) AS msg_count FROM test_valid_data_source.'test_endpoint2' alias LEFT JOIN test_valid_data_source.test_table2 alias2 ON (alias.usename = alias2.username) GROUP BY alias.usename ORDER BY msg_count DESC LIMIT 1"
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:model,:update} - confirm update" do
    case_result = case DV.get_model("test_valid_model") do
      {:ok,defs} ->
        defs.query == "SELECT alias.usename AS username,COUNT(alias2.message) AS msg_count FROM test_valid_data_source.'test_endpoint2' alias LEFT JOIN test_valid_data_source.test_table2 alias2 ON (alias.usename = alias2.username) GROUP BY alias.usename ORDER BY msg_count DESC LIMIT 1"
      _ -> false
    end
    assert case_result,"update to model failed!"
  end
  test "APIV1.handle {:model,:get}" do
    payload = %{
      "action" => "get_model",
      "model" => "test_valid_model"
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:model,:update} - missing" do
    payload = %{
      "action" => "update_model",
      "model" => "test_missing_model",
      "query" => "SELECT alias.usename AS username,COUNT(alias2.message) AS msg_count FROM test_valid_data_source.'test_endpoint2' alias LEFT JOIN test_valid_data_source.test_table2 alias2 ON (alias.usename = alias2.username) GROUP BY alias.usename ORDER BY msg_count DESC LIMIT 1"
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:model,:update} - invalid" do
    payload = %{
      "action" => "update_model",
      "model" => "test_valid_model",
      "query" => "SELEC"
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end

  # TEST APIV1 - endpoint
  test "APIV1.handle {:endpoint,:add} - valid" do
    payload = %{
      "action" => "add_endpoint",
      "endpoint" => "test_valid_endpoint",
      "model" => "test_valid_model"
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:endpoint,:add} - duplicate" do
    payload = %{
      "action" => "add_endpoint",
      "endpoint" => "test_valid_endpoint",
      "model" => "test_valid_model"
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:endpoint,:add} - invalid" do
    payload = %{
      "action" => "add_endpoint",
      "endpoint" => "test_invalid_endpoint",
      "model" => "invalid_model"
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:endpoint,:update} - valid" do
    payload = %{
      "action" => "update_endpoint",
      "endpoint" => "test_valid_endpoint",
      "model" => "test_valid_model_2"
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:endpoint,:update} - confirm update" do
    case_result = case DV.get_endpoint("test_valid_endpoint") do
      {:ok,defs} ->
        defs.model == "test_valid_model_2"
      _ -> false
    end
    assert case_result,"update to endpoint failed!"
  end
  test "APIV1.handle {:endpoint,:get}" do
    payload = %{
      "action" => "get_endpoint",
      "endpoint" => "test_valid_endpoint"
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:endpoint,:update} - missing" do
    payload = %{
      "action" => "update_endpoint",
      "endpoint" => "test_missing_endpoint",
      "model" => "test_valid_model_2"
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:endpoint,:update} - invalid" do
    payload = %{
      "action" => "update_endpoint",
      "endpoint" => "test_valid_endpoint",
      "model" => "invalid_model"
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end

  # TEST - End-to-End
  test "End-to-End - Create Temp File (CSV)",%{tmp_dir: tmp_dir} do
    filename = "#{tmp_dir}/one.csv"
    data = [
      "id,name",
      "1,Testing",
      "2,Two",
      "3,JOIN",
    ] |> Enum.join("\n")
    assert :ok = File.write(filename,data,[:raw])
  end
  test "End-to-End - Create Temp File (JSON)",%{tmp_dir: tmp_dir} do
    filename = "#{tmp_dir}/two.json"
    data = """
      {"result": [
        {
          "id": 1,
          "category": "A"
        },
        {
        "id": 2,
        "category": "Part"
        },
        {
          "id": 3,
          "category": "Query"
        }
      ]
    }
  """
    assert :ok = File.write(filename,data,[:raw])
  end
  test "End-to-End - Add Data Source (CSV)",%{tmp_dir: tmp_dir} do
    payload = %{
      "action" => "add_data_source",
      "data_source" => "csv_data_source",
      "type" => "CSV",
      "version" => 1,
      "path" => tmp_dir,
      "field_separator" => ","
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "End-to-End - Add Data Source (JSON)",%{tmp_dir: tmp_dir} do
    payload = %{
      "action" => "add_data_source",
      "data_source" => "json_data_source",
      "type" => "JSON",
      "version" => 1,
      "path" => tmp_dir,
      "result_path" => "$.result[*]"
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "End-to-End - Add Model" do
    payload = %{
      "action" => "add_model",
      "model" => "end_to_end_model",
      "query" => "SELECT csv.name AS name,json.category AS category FROM csv_data_source.'one.csv' csv LEFT JOIN json_data_source.'two.json' json ON (csv.id = json.id) ORDER BY csv.id ASC"
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "End-to-End - Add Endpoint" do
    payload = %{
      "action" => "add_endpoint",
      "model" => "end_to_end_model",
      "endpoint" => "end_to_end_endpoint"
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "End-to-End - APV1.handle {:endpoint,:run}" do
    payload = %{
      "action" => "run_endpoint",
      "endpoint" => "end_to_end_endpoint"
    }
    case APIV1.handle(payload,%{username: "test_user"},:rest) do
      {:ok,payload} ->
        payload = decode_json(payload)
        request_id = get_in(payload,["data","request_id"])
        result_resp = poll_request(request_id)
        assert %{"status" => "COMPLETED"} = result_resp
        result_set = get_result(request_id)
        validate_result_set(result_set)
      _ -> flunk "unable to run end_to_end_endpoint!"
    end
  end
  test "End-to-End - APV1.handle {:query,:run}" do
    payload = %{
      "action" => "run_query",
      "query" => "SELECT csv.name AS name,json.category AS category FROM csv_data_source.'one.csv' csv LEFT JOIN json_data_source.'two.json' json ON (csv.id = json.id) ORDER BY csv.id ASC"
    }
    case APIV1.handle(payload,%{username: "test_user"},:rest) do
      {:ok,payload} ->
        payload = decode_json(payload)
        request_id = get_in(payload,["data","request_id"])
        result_resp = poll_request(request_id)
        assert %{"status" => "COMPLETED"} = result_resp
        result_set = get_result(request_id)
        validate_result_set(result_set)
      _ -> flunk "unable to run raw query in end-to-end test!"
    end
  end
  defp validate_result_set(result_set) do
    cmp_result = %{
      "columns" => ["name","category"],
      "rows" => [
        ["Testing","A"],
        ["Two","Part"],
        ["JOIN","Query"]
      ]
    }
    assert (cmp_result == result_set),"result sets differ!"
  end
  defp decode_json(payload) do
     case Jason.decode(payload) do
      {:ok,resp} -> resp
      _ -> flunk "unable to decode API response!"
     end
  end
  defp poll_request(request_id,attempts \\ 0) do
    payload = %{
      "action" => "poll_request",
      "request_id" => request_id
    }
    case APIV1.handle(payload,%{username: "test_user"},:rest) do
      {:ok,payload} ->
        payload = Map.get(decode_json(payload),"data")
        case payload do
          %{"end_time" => nil} ->
            Process.sleep(2000)
            if attempts <= 3 do poll_request(request_id,attempts+1) else flunk "request incomplete after 3 attempts!" end
          _ -> payload
        end
      _ -> flunk "failed to poll request!"
    end
  end
  defp get_result(request_id) do
    payload = %{
      "action" => "get_result",
      "request_id" => request_id
    }
    case APIV1.handle(payload,%{username: "test_user"},:rest) do
      {:ok,{:file,fname}} ->
        Map.get(decode_json(File.read!(fname)),"data")
      _ -> flunk "failed to get result set!"
    end
  end

  # TEST APIV1 - Deletions

  test "APIV1.handle {:endpoint,:delete} - valid" do
    payload = %{
      "action" => "delete_endpoint",
      "endpoint" => "test_valid_endpoint",
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:endpoint,:delete} - missing" do
    payload = %{
      "action" => "delete_endpoint",
      "endpoint" => "test_valid_endpoint",
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end

  test "APIV1.handle {:model,:delete} - valid" do
    payload = %{
      "action" => "delete_model",
      "model" => "test_valid_model",
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:model,:delete} - missing" do
    payload = %{
      "action" => "delete_model",
      "model" => "test_valid_model",
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:model,:delete} - valid (_2)" do
    payload = %{
      "action" => "delete_model",
      "model" => "test_valid_model_2",
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:model,:delete} - missing (_2)" do
    payload = %{
      "action" => "delete_model",
      "model" => "test_valid_model_2",
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end

  test "APIV1.handle {:data_source,:delete} - valid" do
    payload = %{
      "action" => "delete_data_source",
      "data_source" => "test_valid_data_source",
    }
    assert {:ok,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
  test "APIV1.handle {:data_source,:delete} - missing" do
    payload = %{
      "action" => "delete_data_source",
      "data_source" => "test_valid_data_source",
    }
    assert {:error,_,_} = APIV1.handle(payload,%{username: "test_user"},:rest)
  end
end

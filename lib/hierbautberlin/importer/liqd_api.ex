defmodule Hierbautberlin.Importer.LiqdApi do
  def fetch_data(http_connection, url, collection_key \\ "results", prev_result \\ []) do
    response =
      http_connection.get!(
        url,
        ["User-Agent": "hierbautberlin.de"],
        timeout: 60_000,
        recv_timeout: 60_000
      )

    if response.status_code != 200 do
      prev_result
    else
      json = Jason.decode!(response.body)

      result = prev_result ++ json[collection_key]

      if json["next"] do
        fetch_data(http_connection, json["next"], collection_key, result)
      else
        result
      end
    end
  end
end

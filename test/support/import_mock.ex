defmodule Hierbautberlin.ImportMock do
  def get!("https://www.infravelo.de/api/v1/projects/") do
    {:ok, html} = File.read("./test/support/data/infravelo/first.json")
    %{body: html, headers: [], status_code: 200}
  end

  def get!("https://www.infravelo.de/api/v1/projects/50/50/") do
    {:ok, html} = File.read("./test/support/data/infravelo/second.json")
    %{body: html, headers: [], status_code: 200}
  end
end

defmodule HierbautberlinWeb.Plugs.PlausibleProxyTest do
  use HierbautberlinWeb.ConnCase, async: false

  alias HierbautberlinWeb.Plugs.PlausibleProxy

  @script_id "pa-test123"

  describe "with tracking enabled" do
    setup do
      Application.put_env(:hierbautberlin, :plausible_script, @script_id)
      :persistent_term.erase({PlausibleProxy, @script_id})

      on_exit(fn ->
        Application.delete_env(:hierbautberlin, :plausible_script)
        :persistent_term.erase({PlausibleProxy, @script_id})
      end)
    end

    test "serves the script of the site and caches it", %{conn: conn} do
      Req.Test.expect(PlausibleProxy, fn plausible ->
        assert plausible.host == "plausible.io"
        assert plausible.request_path == "/js/#{@script_id}.js"
        Plug.Conn.send_resp(plausible, 200, "console.log('plausible')")
      end)

      conn = get(conn, PlausibleProxy.script_path())
      assert response(conn, 200) == "console.log('plausible')"
      assert response_content_type(conn, :js) =~ "application/javascript"

      # the second request is served from the cache, the stub expects only one call
      assert build_conn() |> get(PlausibleProxy.script_path()) |> response(200)
    end

    test "forwards events with the address and browser of the visitor", %{conn: conn} do
      Req.Test.expect(PlausibleProxy, fn plausible ->
        assert plausible.method == "POST"
        assert plausible.request_path == "/api/event"
        assert Plug.Conn.get_req_header(plausible, "user-agent") == ["Test Browser"]

        assert Plug.Conn.get_req_header(plausible, "x-forwarded-for") == [
                 "203.0.113.7, 127.0.0.1"
               ]

        {:ok, body, plausible} = Plug.Conn.read_body(plausible)
        assert body == ~s({"n":"pageview","u":"https://hierbautberlin.de/map"})
        Plug.Conn.send_resp(plausible, 202, "ok")
      end)

      conn =
        conn
        |> put_req_header("content-type", "text/plain")
        |> put_req_header("user-agent", "Test Browser")
        |> put_req_header("x-forwarded-for", "203.0.113.7")
        |> post(
          PlausibleProxy.event_path(),
          ~s({"n":"pageview","u":"https://hierbautberlin.de/map"})
        )

      assert response(conn, 202) == "ok"
    end

    test "adds the script to the pages", %{conn: conn} do
      html = conn |> get(~p"/impressum") |> html_response(200)
      assert html =~ ~s(src="/js/hbb.js")
      assert html =~ ~s(endpoint: "/api/hbb-event")
    end
  end

  describe "without a script id" do
    test "tracking is disabled", %{conn: conn} do
      assert conn |> get(PlausibleProxy.script_path()) |> response(404)

      assert build_conn()
             |> put_req_header("content-type", "text/plain")
             |> post(PlausibleProxy.event_path(), "{}")
             |> response(404)

      refute build_conn() |> get(~p"/impressum") |> html_response(200) =~ "hbb.js"
    end
  end
end

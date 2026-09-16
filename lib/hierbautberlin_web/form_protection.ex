defmodule HierbautberlinWeb.FormProtection do
  @moduledoc """
  Keeps simple bots away from public forms without a captcha.

  Two checks:

    * a honeypot field that is hidden from people (and screen readers), bots
      fill it in
    * a signed timestamp of when the form was rendered: a submit faster than
      `@min_seconds` is a script, a missing or forged token means the form was
      never loaded

  Render `form_protection_fields/1` inside the form and call `check/1` with the
  params of the submit.
  """
  use Phoenix.Component

  require Logger

  @salt "form protection"
  @min_seconds 2
  @max_seconds 24 * 60 * 60

  @honeypot_field "website"
  @token_field "form_token"

  @doc """
  Hidden fields for the form: the honeypot and the signed timestamp.
  """
  attr :now, :integer, default: nil, doc: "unix seconds, only for tests"

  def form_protection_fields(assigns) do
    assigns =
      assigns
      |> assign(:token, token(assigns.now || now()))
      |> assign(:honeypot_field, @honeypot_field)
      |> assign(:token_field, @token_field)

    ~H"""
    <input type="hidden" name={@token_field} value={@token} />
    <div class="form-protection" aria-hidden="true">
      <label for={"form_protection_" <> @honeypot_field}>Bitte leer lassen</label>
      <input
        type="text"
        id={"form_protection_" <> @honeypot_field}
        name={@honeypot_field}
        value=""
        autocomplete="off"
        tabindex="-1"
      />
    </div>
    """
  end

  @doc """
  Signed token with the time the form was rendered.
  """
  def token(rendered_at \\ now()) do
    Phoenix.Token.sign(HierbautberlinWeb.Endpoint, @salt, rendered_at)
  end

  @doc """
  Checks the params of a submitted form.

  Returns `:ok`, `{:error, :honeypot}` when the honeypot was filled in, or
  `{:error, :too_fast}` / `{:error, :invalid_token}` when the form wasn't
  loaded by a person.
  """
  def check(params, form_name \\ "form") do
    result =
      if params[@honeypot_field] in [nil, ""],
        do: check_token(params[@token_field]),
        else: {:error, :honeypot}

    with {:error, reason} <- result do
      Logger.info("Blocked #{form_name} submit: #{reason}")
    end

    result
  end

  defp check_token(token) when is_binary(token) do
    case Phoenix.Token.verify(HierbautberlinWeb.Endpoint, @salt, token, max_age: @max_seconds) do
      {:ok, rendered_at} when is_integer(rendered_at) ->
        if now() - rendered_at >= @min_seconds, do: :ok, else: {:error, :too_fast}

      _ ->
        {:error, :invalid_token}
    end
  end

  defp check_token(_), do: {:error, :invalid_token}

  defp now, do: System.system_time(:second)
end

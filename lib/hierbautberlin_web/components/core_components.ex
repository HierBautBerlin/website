defmodule HierbautberlinWeb.CoreComponents do
  @moduledoc """
  Shared UI components.
  """
  use Phoenix.Component
  use Gettext, backend: HierbautberlinWeb.Gettext

  alias Phoenix.LiveView.JS

  @svg_path Path.expand("../../../priv/static/svg/generic", __DIR__)
  @svgs (for file <- File.ls!(@svg_path), String.ends_with?(file, ".svg"), into: %{} do
           path = Path.join(@svg_path, file)
           @external_resource path

           svg =
             path
             |> File.read!()
             |> String.replace(~r/<\?xml.*?\?>\s*/, "")
             |> String.trim()

           {Path.rootname(file), svg}
         end)

  @svg_files @svg_path |> File.ls!() |> Enum.sort()

  # Recompile when an SVG file was added or removed (changes are tracked by @external_resource)
  def __mix_recompile__?, do: @svg_path |> File.ls!() |> Enum.sort() != @svg_files

  @doc """
  Renders one of the SVG files from `priv/static/svg/generic` inline.
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil
  attr :alt, :string, default: nil

  def svg_image(assigns) do
    svg = Map.fetch!(@svgs, assigns.name)

    attributes =
      [class: assigns.class, "aria-label": assigns.alt, role: assigns.alt && "img"]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map_join(fn {key, value} ->
        ~s( #{key}="#{value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()}")
      end)

    assigns =
      assign(assigns, :svg, String.replace(svg, "<svg", "<svg" <> attributes, global: false))

    ~H"{Phoenix.HTML.raw(@svg)}"
  end

  @doc """
  Renders the flash messages.
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <p :if={msg = Phoenix.Flash.get(@flash, :info)} class="alert alert-info" role="alert">{msg}</p>
    <p :if={msg = Phoenix.Flash.get(@flash, :error)} class="alert alert-danger" role="alert">
      {msg}
    </p>
    """
  end

  @doc """
  Renders a modal.

  Either `return_to` (a path patched to on close) or `on_close` (a `JS` command
  or event name) needs to be given.
  """
  attr :id, :string, required: true
  attr :return_to, :string, default: nil
  attr :on_close, :any, default: nil
  slot :inner_block, required: true

  def modal(assigns) do
    assigns = assign(assigns, :close, close_action(assigns))

    ~H"""
    <div
      id={@id}
      class="phx-modal"
      phx-window-keydown={@close}
      phx-key="escape"
      phx-mounted={JS.focus(to: "##{@id}-content")}
    >
      <div class="phx-modal-inner" role="dialog" aria-modal="true" phx-click-away={@close}>
        <button type="button" phx-click={@close} class="phx-modal-close" aria-label="Schließen">
          &times;
        </button>
        <%!-- The content itself gets the focus: focusing the first link or button
             would scroll long texts down to it --%>
        <div id={"#{@id}-content"} class="phx-modal-content" tabindex="-1">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  defp close_action(%{return_to: return_to}) when is_binary(return_to),
    do: JS.patch(return_to)

  defp close_action(%{on_close: %JS{} = js}), do: js
  defp close_action(%{on_close: event}) when is_binary(event), do: JS.push(event)

  @doc """
  Renders a label, an input and its errors for a form field.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :type, :string, default: "text"
  attr :label, :string, default: nil
  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :value, :any
  attr :rest, :global, include: ~w(required autocomplete)

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns.field.value)
      end)

    ~H"""
    <label>
      <input type="hidden" name={@name || @field.name} value="false" />
      <input
        type="checkbox"
        id={@id || @field.id}
        name={@name || @field.name}
        value="true"
        checked={@checked}
        {@rest}
      />
      {@label}
    </label>
    """
  end

  def input(assigns) do
    assigns = assign_new(assigns, :value, fn -> assigns.field.value end)

    ~H"""
    <label for={@id || @field.id}>{@label || Phoenix.Naming.humanize(@field.field)}</label>
    <input
      type={@type}
      name={@name || @field.name}
      id={@id || @field.id}
      value={Phoenix.HTML.Form.normalize_value(@type, @value)}
      {@rest}
    />
    <span :for={error <- @field.errors} class="invalid-feedback">{translate_error(error)}</span>
    """
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(HierbautberlinWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(HierbautberlinWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Converts plain text into HTML paragraphs. Paragraphs are separated by empty
  lines, single line breaks become `<br>`.
  """
  def text_to_html(text) do
    text
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.map_join(fn paragraph ->
      lines =
        paragraph
        |> String.split("\n")
        |> Enum.map_join("<br>\n", fn line ->
          line |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        end)

      "<p>#{lines}</p>\n"
    end)
    |> Phoenix.HTML.raw()
  end

  @doc """
  Formats a date as `DD.MM.YYYY`, timestamps in Berlin time (the UTC date of
  midnight in Berlin is the day before).
  """
  def format_date(nil), do: ""

  def format_date(%DateTime{} = datetime) do
    datetime |> DateTime.shift_zone!("Europe/Berlin") |> Calendar.strftime("%d.%m.%Y")
  end

  def format_date(%NaiveDateTime{} = datetime),
    do: datetime |> DateTime.from_naive!("Etc/UTC") |> format_date()

  def format_date(date), do: Calendar.strftime(date, "%d.%m.%Y")
end

defmodule HierbautberlinWeb.MapComponents do
  @moduledoc """
  Components for the detail views on the map.
  """
  use HierbautberlinWeb, :html

  alias Hierbautberlin.GeoData.{GeoItem, GeoPlace, GeoStreet, GeoStreetNumber, NewsItem}
  alias HierbautberlinWeb.MapRouteHelpers

  attr :item, :any, required: true

  def details(%{item: %GeoItem{}} = assigns) do
    ~H"""
    <h3 class="details--content--title">
      <div style={"padding-left: 0.5rem; border-left: 5px solid #{@item.source.color}"}>
        {@item.title}
      </div>
    </h3>

    <h4 :if={!blank?(@item.subtitle)}>{@item.subtitle}</h4>

    <div class="details--labels">
      <span :if={@item.participation_open} class="label--participation">Beteiligung möglich</span>
      <span :if={@item.state} class="label--state">{state_to_text(@item)}</span>
      <span class="label--source">{@item.source.name}</span>
    </div>

    {if !blank?(@item.description), do: text_to_html(@item.description)}

    <div :if={!blank?(@item.url)} class="details--links">
      <div><a href={@item.url} target="_blank" rel="noopener noreferrer">&gt; Details</a></div>
      <div :if={!blank?(@item.additional_link_name)}>
        <a href={@item.additional_link} target="_blank" rel="noopener noreferrer">
          &gt; {@item.additional_link_name}
        </a>
      </div>
    </div>

    <p :if={@item.date_start || @item.date_end}>
      Datum:
      <%= if @item.date_start do %>
        {format_date(@item.date_start)}
      <% end %>
      <%= if @item.date_end && @item.date_start != @item.date_end do %>
        - {format_date(@item.date_end)}
      <% end %>
    </p>

    <.copyright source={@item.source} />
    """
  end

  def details(%{item: %NewsItem{}} = assigns) do
    ~H"""
    <h3 class="details--content--title">
      <div style={"padding-left: 0.5rem; border-left: 5px solid #{@item.source.color}"}>
        {@item.title}
      </div>
    </h3>

    <div class="details--labels">
      <span class="label--source">{@item.source.name}</span>
    </div>

    {if !blank?(@item.content), do: text_to_html(@item.content)}

    <div :if={!blank?(@item.url)} class="details--links">
      <div><a href={@item.url} target="_blank" rel="noopener noreferrer">&gt; Details</a></div>
    </div>

    <p :if={@item.published_at}>
      Veröffentlicht am: {format_date(@item.published_at)}
    </p>

    <.copyright source={@item.source} />
    """
  end

  def details(%{item: %GeoStreet{}} = assigns) do
    ~H"""
    <h3 class="details--content--title">{@item.name}</h3>
    <.news_items_list news_items={@item.news_items} />
    """
  end

  def details(%{item: %GeoStreetNumber{}} = assigns) do
    ~H"""
    <h3 class="details--content--title">{@item.geo_street.name} {@item.number}</h3>
    <.news_items_list news_items={@item.news_items} />
    """
  end

  def details(%{item: %GeoPlace{}} = assigns) do
    ~H"""
    <h3 class="details--content--title">{@item.name}</h3>
    <.news_items_list news_items={@item.news_items} />
    """
  end

  attr :item, :any, required: true
  attr :shape, :string, default: nil, doc: "GeoJSON from `MapFeatures.details_shape/1`"

  @doc """
  A small map with the shape of the entry (polygons, lines and points) in the
  color of its source, see `assets/js/detailsMap.ts`.
  """
  def details_map(assigns) do
    assigns =
      assign(assigns,
        id: "details-map-#{MapRouteHelpers.type_of_item(assigns.item)}-#{assigns.item.id}",
        color: map_color(assigns.item),
        background_color: map_background_color(assigns.item)
      )

    ~H"""
    <div
      :if={@shape}
      id={@id}
      class="details--map"
      phx-hook="DetailsMap"
      phx-update="ignore"
      role="region"
      aria-label="Karte mit dem Ort des Eintrags"
      data-shape={@shape}
      data-color={@color}
      data-background-color={@background_color}
    >
    </div>
    """
  end

  defp map_color(%{source: %{color: color}}) when is_binary(color), do: color
  defp map_color(_item), do: "#2f7d65"

  # lines and polygons, like on the big map
  defp map_background_color(%{source: %{background_color: color}}) when is_binary(color),
    do: color

  defp map_background_color(item), do: map_color(item)

  @doc """
  Shares the link to the entry with the Web Share API or copies it, see
  `assets/js/shareButton.ts`.
  """
  def share_button(assigns) do
    assigns =
      assign(assigns,
        id: "share-#{MapRouteHelpers.type_of_item(assigns.item)}-#{assigns.item.id}",
        url: MapRouteHelpers.share_link(assigns.item),
        title: share_title(assigns.item)
      )

    ~H"""
    <div
      id={@id}
      class="details--share"
      phx-hook="ShareButton"
      phx-update="ignore"
      data-url={@url}
      data-title={@title}
    >
      <span class="details--share--status" role="status" aria-live="polite"></span>
      <button type="button" class="details--share--button">
        <.svg_image name="share" class="details--share--icon" />
        <span>Teilen</span>
      </button>
    </div>
    """
  end

  defp share_title(%GeoStreetNumber{} = item), do: "#{item.geo_street.name} #{item.number}"
  defp share_title(%{title: title}), do: title
  defp share_title(%{name: name}), do: name

  attr :source, :any, required: true

  defp copyright(assigns) do
    ~H"""
    <div :if={!blank?(@source.copyright)}>
      &copy;
      <a href={@source.url} target="_blank" rel="noopener noreferrer">
        {@source.copyright}
      </a>
    </div>
    """
  end

  attr :news_items, :list, required: true

  def news_items_list(assigns) do
    ~H"""
    <ul class="details--news-items">
      <li
        :for={item <- @news_items}
        class="details--news-item"
        id={"news-list-item-#{item.id}"}
        phx-click="showDetails"
        phx-value-item-type="news_item"
        phx-value-item-id={item.id}
      >
        <h3 class="details--news-item--title">
          <div style={"padding-left: 0.5rem; border-left: 5px solid #{item.source.color}"}>
            <a
              id={"news-details-#{item.id}"}
              href={"/map?details=#{item.id}&detailsType=news_item"}
              data-details-link
            >
              {item.title}
            </a>
          </div>
        </h3>
        <p class="details--news-item--content">{item.content}</p>

        <span class="label--published">
          {format_date(item.published_at)}
        </span>
        <span class="label--source">{item.source.name}</span>
      </li>
    </ul>
    """
  end
end

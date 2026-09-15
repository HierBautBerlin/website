defmodule HierbautberlinWeb.StateHelpers do
  def state_to_text(item) do
    case item.state do
      "intended" -> "Geplant"
      "in_preparation" -> "In Vorbereitung"
      "in_planning" -> "In Planung"
      "under_construction" -> "Im Bau"
      "active" -> "Aktiv"
      "finished" -> "Abgeschlossen"
    end
  end
end

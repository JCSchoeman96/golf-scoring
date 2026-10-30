defmodule GolfScoring.Competition do
  @moduledoc "Competition and Event lifecycle domain."

  use Ash.Domain

  resources do
    resource GolfScoring.Competition.Event do
      define :cancel_event, action: :cancel_event
      define :archive_event, action: :archive_event
    end
  end
end

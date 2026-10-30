defmodule GolfScoring.GolfCatalog.TeeRatingProfile.HoleRating do
  @moduledoc "Per-hole rating facts for one TeeRatingProfile."

  use Ash.Resource,
    data_layer: :embedded

  attributes do
    attribute :course_hole_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :par, :integer do
      allow_nil? false
      public? true
      constraints min: 3, max: 7
    end

    attribute :stroke_index, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :distance_mm, :integer do
      allow_nil? true
      public? true
      constraints min: 1
    end
  end
end

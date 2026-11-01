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

    attribute :distance_m, :integer do
      allow_nil? true
      public? true
      constraints min: 1
    end

    attribute :plus_stroke_order, :integer do
      allow_nil? true
      public? true
      constraints min: 1, max: 8
    end
  end
end

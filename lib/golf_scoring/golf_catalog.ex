defmodule GolfScoring.GolfCatalog do
  @moduledoc "Reusable physical golf course catalog."

  use Ash.Domain

  resources do
    resource GolfScoring.GolfCatalog.Course do
      define :create_course, action: :create_course, args: [:event_id]
      define :update_course, action: :update_course, args: [:event_id]
      define :archive_course, action: :archive_course, args: [:event_id]
    end

    resource GolfScoring.GolfCatalog.CourseHole do
      define :configure_course_hole, action: :configure_course_hole, args: [:event_id]
    end
  end
end

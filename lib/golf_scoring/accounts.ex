defmodule GolfScoring.Accounts do
  @moduledoc "Staff account domain."

  use Ash.Domain

  resources do
    resource GolfScoring.Accounts.StaffUser
  end
end

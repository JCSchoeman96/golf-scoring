defmodule GolfScoring.Accounts do
  @moduledoc "Staff account domain."

  use Ash.Domain

  resources do
    resource GolfScoring.Accounts.StaffUser do
      define :grant_system_admin, action: :grant_system_admin
      define :revoke_system_admin, action: :revoke_system_admin
    end
  end
end

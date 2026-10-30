defmodule GolfScoring.Accounts do
  @moduledoc "Staff account domain."

  use Ash.Domain

  resources do
    resource GolfScoring.Accounts.StaffUser do
      define :grant_system_admin, action: :grant_system_admin
      define :revoke_system_admin, action: :revoke_system_admin
      define :suspend_staff_user, action: :suspend_staff_user
      define :reactivate_staff_user, action: :reactivate_staff_user
      define :disable_staff_user, action: :disable_staff_user
    end
  end
end

defmodule GolfScoring.Audit do
  @moduledoc "Audit domain for durable operational history."

  use Ash.Domain

  resources do
    resource GolfScoring.Audit.AuditEvent do
      define :record_staff_event, action: :record_staff_event
      define :record_system_event, action: :record_system_event
    end
  end
end

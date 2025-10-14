defmodule Ysc.MessagePassingEvents do
  defmodule AgendaAdded do
    defstruct agenda: nil
  end

  defmodule AgendaDeleted do
    defstruct agenda: nil
  end

  defmodule AgendaUpdated do
    defstruct agenda: nil
  end

  defmodule AgendaRepositioned do
    defstruct agenda: nil
  end

  defmodule AgendaItemDeleted do
    defstruct agenda_item: nil
  end

  defmodule AgendaItemRepositioned do
    defstruct agenda_item: nil
  end

  defmodule AgendaItemAdded do
    defstruct agenda_item: nil
  end

  defmodule AgendaItemUpdated do
    defstruct agenda_item: nil
  end

  defmodule EventAdded do
    defstruct event: nil
  end

  defmodule EventUpdated do
    defstruct event: nil
  end

  defmodule EventDeleted do
    defstruct event: nil
  end

  defmodule TicketTierAdded do
    defstruct ticket_tier: nil
  end

  defmodule TicketTierUpdated do
    defstruct ticket_tier: nil
  end

  defmodule TicketTierDeleted do
    defstruct ticket_tier: nil
  end

  defmodule TicketCreated do
    defstruct ticket: nil
  end
end

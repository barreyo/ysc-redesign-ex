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
end

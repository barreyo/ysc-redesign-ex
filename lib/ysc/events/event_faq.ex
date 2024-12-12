defmodule Ysc.Events.FaqQuestion do
  use Ecto.Schema

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "faq_questions" do
    belongs_to :event, Ysc.Events.Event, foreign_key: :event_id, references: :id

    field :question, :string
    field :answer, :string

    timestamps()
  end
end

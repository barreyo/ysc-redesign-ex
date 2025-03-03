defmodule Ysc.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"
  def valid_user_first_name, do: "John"
  def valid_user_last_name, do: "Doe"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password(),
      first_name: valid_user_first_name(),
      last_name: valid_user_last_name(),
      phone_number: "+14159098268",
      state: :active,
      role: :member
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Ysc.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured} = fun.(&"[TOKEN]#{&1}[TOKEN]")

    case captured do
      [token] when is_binary(token) ->
        token

      %{text: text} ->
        [_, token | _] = String.split(text, "[TOKEN]")
        token

      # Handle the email notification format
      %{text_body: token} ->
        token

      text when is_binary(text) ->
        [_, token | _] = String.split(text, "[TOKEN]")
        token
    end
  end
end

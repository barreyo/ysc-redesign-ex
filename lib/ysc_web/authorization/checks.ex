defmodule YscWeb.Authorization.Policy.Checks do
  alias Ysc.Accounts.User

  def own_resource(%User{id: id}, %{user_id: id}) when is_binary(id), do: true
  def own_resource(_, _), do: false

  def own_resource(%User{id: id}, %{user_id: id}, _opts) when is_binary(id), do: true
  def own_resource(_, _, _), do: false

  def role(%User{role: role}, _object, role), do: true
  def role(_, _, _), do: false
end

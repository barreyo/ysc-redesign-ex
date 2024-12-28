ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Ysc.Repo, :manual)

Mox.defmock(Ysc.AccountsMock, for: Ysc.Accounts)
Application.put_env(:ysc, :accounts, Ysc.AccountsMock)

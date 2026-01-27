ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Ysc.Repo, :manual)

# Suppress expected test errors by replacing the console backend with a filtered one
# Remove all existing backends first
Logger.remove_backend(:console)
# Add our custom filtered backend
Logger.add_backend(Ysc.TestLoggerBackend)

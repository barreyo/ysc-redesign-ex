ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Ysc.Repo, :manual)

# Suppress expected test errors by replacing the console backend with a filtered one
# Remove all existing backends first
Logger.remove_backend(:console)
# Add our custom filtered backend
Logger.add_backend(Ysc.TestLoggerBackend)

# Suppress DBConnection "owner/client exited" logs in test. These are normal when
# each test's sandbox owner process exits; they are not failures. Disabling
# db_connection logging avoids relying on the custom backend to filter them.
Logger.put_application_level(:db_connection, false)

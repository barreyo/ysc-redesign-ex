defmodule YscWeb.Layouts.SwiftUI do
  use YscNative, [:layout, format: :swiftui]

  embed_templates "layouts_swiftui/*"
end

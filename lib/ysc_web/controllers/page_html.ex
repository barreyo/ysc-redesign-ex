defmodule YscWeb.PageHTML do
  use YscWeb, :html

  embed_templates "page_html/*"

  defp atom_to_readable(atom) do
    atom
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end

defmodule YscWeb.PageHTML do
  use YscWeb, :html

  embed_templates "page_html/*"

  defp atom_to_readable(atom) when is_binary(atom) do
    atom
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp atom_to_readable(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end

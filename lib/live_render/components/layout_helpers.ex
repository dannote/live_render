defmodule LiveRender.Components.LayoutHelpers do
  @moduledoc false

  def gap_class(0), do: "gap-0"
  def gap_class(1), do: "gap-1"
  def gap_class(2), do: "gap-2"
  def gap_class(3), do: "gap-3"
  def gap_class(4), do: "gap-4"
  def gap_class(5), do: "gap-5"
  def gap_class(6), do: "gap-6"
  def gap_class(8), do: "gap-8"
  def gap_class(_), do: "gap-3"
end

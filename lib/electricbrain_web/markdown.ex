defmodule ElectricbrainWeb.Markdown do
  @extensions [
    strikethrough: true,
    table: true,
    autolink: true,
    tasklist: true,
    footnotes: true
  ]

  def to_html(body) when is_binary(body) do
    MDEx.to_html!(body, extension: @extensions, render: [unsafe: false])
  end

  def to_html(_), do: ""
end

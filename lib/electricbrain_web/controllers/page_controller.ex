defmodule ElectricbrainWeb.PageController do
  use ElectricbrainWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

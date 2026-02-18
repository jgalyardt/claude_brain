defmodule EvoWeb.PageController do
  use EvoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

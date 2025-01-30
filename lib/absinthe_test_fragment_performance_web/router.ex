defmodule AbsintheTestFragmentPerformanceWeb.Router do
  use AbsintheTestFragmentPerformanceWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :api

    forward "/graphiql", Absinthe.Plug.GraphiQL, schema: AbsintheTestFragmentPerformanceWeb.Schema

    forward "/", Absinthe.Plug, schema: AbsintheTestFragmentPerformanceWeb.Schema
  end
end

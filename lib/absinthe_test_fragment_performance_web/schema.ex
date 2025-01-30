defmodule AbsintheTestFragmentPerformanceWeb.Schema do
  use Absinthe.Schema

  interface :reading do
    field(:id, :id)

    resolve_type(fn
      %{description: _}, _ -> :book
      %{body: _}, _ -> :post
      _, _ -> nil
    end)
  end

  object :post do
    field(:id, :id)
    field(:title, :string)
    field(:body, :string)

    field :author, :author do
      resolve(fn _, _ ->
        {:ok, nil}
      end)
    end

    interface(:reading)
  end

  object :book do
    field(:id, :id)
    field(:title, :string)
    field(:description, :string)

    field :author, :author do
      resolve(fn _, _ ->
        {:ok, nil}
      end)
    end

    interface(:reading)
  end

  object :author do
    field(:id, :id)
    field(:name, :string)
  end

  query do
    @desc "Get all posts"
    field :readings, list_of(:reading) do
      resolve(fn _, _ ->
        {:ok, []}
      end)
    end
  end
end

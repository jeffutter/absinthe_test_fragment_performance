defmodule Base26 do
  def base26(0), do: "a"

  def base26(n) when n > 0 do
    base26(n, "")
  end

  defp base26(-1, acc), do: acc

  defp base26(n, acc) do
    rem = rem(n, 26)
    char = <<rem + 97::utf8>>
    next = div(n, 26) - 1
    base26(next, char <> acc)
  end
end

defmodule AbsintheTestFragmentPerformance.SchemaBuilder do
  def mod_name(id) when not is_binary(id) do
    id
    |> uc_name()
    |> mod_name()
  end

  def mod_name(id) do
    Module.concat([FragmentBench, :Schema, id])
  end

  def uc_name(id) do
    String.upcase(lc_name(id))
  end

  def lc_name(id) do
    to_string(Base26.base26(id))
  end

  def tc_name(id) do
    String.capitalize(lc_name(id))
  end

  def build_schemas(frag_range) do
    for n <- frag_range do
      uc_name = to_string([65 + n])
      mod_name = mod_name(uc_name)

      build_schema(mod_name, n)
    end
  end

  def query_no_fragments(extra_fields) do
    [
      """
      query {
        things {
          id
          __typename
      """,
      for n <- 0..extra_fields, n != extra_fields do
        [lc_name(n), ~c"\n"]
      end,
      """
        }
      }
      """
    ]
    |> :erlang.iolist_to_binary()
  end

  def query_skip_spread(0, extra_fields), do: query_no_fragments(extra_fields)

  def query_skip_spread(fragments, extra_fields) do
    [
      """
      query ($skip: Boolean!) {
        things {
          id
          __typename
      """,
      for n <- 0..extra_fields, n != extra_fields do
        [lc_name(n), ~c"\n"]
      end,
      spread_fragments(:skip, fragments),
      """
        }
      }
      """,
      spread_fragments_def(fragments)
    ]
    |> :erlang.iolist_to_binary()
  end

  def query_include_spread(0, extra_fields), do: query_no_fragments(extra_fields)

  def query_include_spread(fragments, extra_fields) do
    [
      """
      query ($include: Boolean!) {
        things {
          id
          __typename
      """,
      for n <- 0..extra_fields, n != extra_fields do
        [lc_name(n), ~c"\n"]
      end,
      spread_fragments(:include, fragments),
      """
        }
      }
      """,
      spread_fragments_def(fragments)
    ]
    |> :erlang.iolist_to_binary()
  end

  def query_skip_inline(0, extra_fields), do: query_no_fragments(extra_fields)

  def query_skip_inline(fragments, extra_fields) do
    [
      """
      query ($skip: Boolean!) {
        things {
          id
          __typename
      """,
      for n <- 0..extra_fields, n != extra_fields do
        [lc_name(n), ~c"\n"]
      end,
      inline_fragments(:skip, fragments),
      """
        }
      }
      """
    ]
    |> :erlang.iolist_to_binary()
  end

  def query_include_inline(0, extra_fields), do: query_no_fragments(extra_fields)

  def query_include_inline(fragments, extra_fields) do
    [
      """
      query ($include: Boolean!) {
        things {
          id
          __typename
      """,
      for n <- 0..extra_fields, n != extra_fields do
        [lc_name(n), ~c"\n"]
      end,
      inline_fragments(:include, fragments),
      """
        }
      }
      """
    ]
    |> :erlang.iolist_to_binary()
  end

  defp inline_fragments(skip_or_include, max) do
    for n <- 0..max, n != max do
      inline_fragment(skip_or_include, n)
    end
  end

  defp inline_fragment(:skip, n),
    do: ["... on ", tc_name(n), " @skip(if: $skip) { id __typename }", ~c"\n"]

  defp inline_fragment(:include, n),
    do: ["... on ", tc_name(n), " @include(if: $include) { id __typename }", ~c"\n"]

  defp spread_fragments(skip_or_include, max) do
    for n <- 0..max, n != max do
      spread_fragment(skip_or_include, n)
    end
  end

  defp spread_fragment(:skip, n),
    do: ["... ", tc_name(n), "Fragment @skip(if: $skip)", ~c"\n"]

  defp spread_fragment(:include, n),
    do: ["... ", tc_name(n), "Fragment @include(if: $include)", ~c"\n"]

  defp spread_fragments_def(max) do
    for n <- 0..max, n != max do
      spread_fragment_def(n)
    end
  end

  defp spread_fragment_def(n),
    do: ["fragment ", tc_name(n), "Fragment on ", tc_name(n), " { id __typename }", ~c"\n"]

  def build_schema(name, fragments, max_fields) do
    quote location: :keep do
      defmodule unquote(name) do
        use Absinthe.Schema

        unquote(build_interface(max_fields - fragments))
        unquote_splicing(build_objects(fragments, max_fields - fragments))
        unquote(build_query())

        def query_skip_spread,
          do:
            unquote(__MODULE__).query_skip_spread(
              unquote(fragments),
              unquote(max_fields - fragments)
            )

        def query_include_spread,
          do:
            unquote(__MODULE__).query_include_spread(
              unquote(fragments),
              unquote(max_fields - fragments)
            )

        def query_skip_inline,
          do:
            unquote(__MODULE__).query_skip_inline(
              unquote(fragments),
              unquote(max_fields - fragments)
            )

        def query_include_inline,
          do:
            unquote(__MODULE__).query_include_inline(
              unquote(fragments),
              unquote(max_fields - fragments)
            )
      end
    end
  end

  def build_objects(0, _), do: []

  def build_objects(fragments, extra_fields) do
    for on <- 0..(fragments - 1) do
      obj_lc_name = String.to_atom(lc_name(on))
      build_object(obj_lc_name, extra_fields)
    end
  end

  def build_interface(extra_fields) do
    # Something like this... but can't get the unquote_splicing + field to work, so do it as AST
    # quote do
    #   interface :thing do
    #     field(:id, :id)
    #
    #     # unquote_splicing(
    #     #   for f <- 0..max_fields do
    #     #     field(String.to_atom(SchemaBuilder.lc_name(f)), :string)
    #     #   end
    #     # )
    #
    #     resolve_type(fn
    #       _, _ -> nil
    #     end)
    #   end
    # end

    {:interface, [],
     [
       :thing,
       [
         do:
           {:__block__, [],
            List.flatten([
              {:field, [], [:id, :id]},
              extra_fields(extra_fields),
              {:resolve_type, [],
               [
                 {:fn, [], [{:->, [], [[{:_, [], SchemaBuilder}, {:_, [], SchemaBuilder}], nil]}]}
               ]}
            ])}
       ]
     ]}
  end

  def extra_fields(0), do: []

  def extra_fields(count) do
    for f <- 0..count, f != 0 do
      {:field, [], [String.to_atom(lc_name(f - 1)), :string]}
    end
  end

  def build_query do
    quote location: :keep do
      query do
        field :things, list_of(:thing) do
          resolve(fn _, _ ->
            {:ok, []}
          end)
        end
      end
    end
  end

  def build_object(name, extra_fields) do
    # quote location: :keep do
    #   object unquote(name) do
    #     field(:id, :id)
    #
    #     interface(:thing)
    #   end
    # end
    {:object, [],
     [
       name,
       [
         do:
           {:__block__, [],
            List.flatten([
              {:field, [], [:id, :id]},
              extra_fields(extra_fields),
              {:interface, [], [:thing]}
            ])}
       ]
     ]}
  end

  def build_schema(fragments, max_fields) do
    mod_name = mod_name(uc_name(fragments))

    build_schema(mod_name, fragments, max_fields)
  end

  def define_schema(fragments, max_fields) do
    fragments
    |> build_schema(max_fields)
    |> Code.eval_quoted()

    mod_name(uc_name(fragments))
  end
end

defmodule FragmentBench do
  @no_fragments """
    query {
      readings {
        id
      }
    }
  """

  @skip_fragment_spread """
    query ($skip: Boolean!) {
      readings {
        id
        ... BookFragment @skip(if: $skip)
        ... PostFragment @skip(if: $skip)
      }
    }
    fragment BookFragment on Book {
      author {
        id
      }
      id
    }
    fragment PostFragment on Post {
      author {
        id
      }
      id
    }
  """

  @skip_inline_fragment """
    query ($skip: Boolean!) {
      readings {
        id
        ... on Book @skip(if: $skip) {
          id
          author {
            id
          }
        }
        ... on Post @skip(if: $skip) {
          id
          author {
            id
          }
        }
      }
    }
  """

  @skip_fragment_spread_mixed_directive """
    query ($skip: Boolean!) {
      readings {
        id
        ... BookFragment
        ... PostFragment @skip(if: $skip)
      }
    }
    fragment BookFragment on Book {
      author {
        id
      }
      id
    }
    fragment PostFragment on Post {
      author {
        id
      }
      id
    }
  """

  @skip_inline_fragment_mixed_directive """
    query ($skip: Boolean!) {
      readings {
        id
        ... on Book {
          id
          author {
            id
          }
        }
        ... on Post @skip(if: $skip) {
          id
          author {
            id
          }
        }
      }
    }
  """

  @fragment_spread_no_directive """
    query {
      readings {
        id
        ... BookFragment
        ... PostFragment
      }
    }
    fragment BookFragment on Book {
      author {
        id
      }
      id
    }
    fragment PostFragment on Post {
      author {
        id
      }
      id
    }
  """

  @inline_fragment_no_directive """
    query {
      readings {
        id
        ... on Book {
          id
          author {
            id
          }
        }
        ... on Post {
          id
          author {
            id
          }
        }
      }
    }
  """

  @include_fragment_spread """
    query ($include: Boolean!) {
      readings {
        id
        ... BookFragment @include(if: $include)
        ... PostFragment @include(if: $include)
      }
    }
    fragment BookFragment on Book {
      author {
        id
      }
      id
    }
    fragment PostFragment on Post {
      author {
        id
      }
      id
    }
  """

  @include_inline_fragment """
    query ($include: Boolean!) {
      readings {
        id
        ... on Book @include(if: $include) {
          id
          author {
            id
          }
        }
        ... on Post @include(if: $include) {
          id
          author {
            id
          }
        }
      }
    }
  """

  @include_fragment_spread_mixed_directive """
    query ($include: Boolean!) {
      readings {
        id
        ... BookFragment
        ... PostFragment @include(if: $include)
      }
    }
    fragment BookFragment on Book {
      author {
        id
      }
      id
    }
    fragment PostFragment on Post {
      author {
        id
      }
      id
    }
  """

  @include_inline_fragment_mixed_directive """
    query ($include: Boolean!) {
      readings {
        id
        ... on Book {
          id
          author {
            id
          }
        }
        ... on Post @include(if: $include) {
          id
          author {
            id
          }
        }
      }
    }
  """

  def setup do
    queries = [
      # {:no_fragments, @no_fragments, %{}},
      {:skip_false_fragment_spread, @skip_fragment_spread, %{"skip" => false}},
      {:skip_true_fragment_spread, @skip_fragment_spread, %{"skip" => true}},
      # {:skip_fragment_spread_mixed_directive, @skip_fragment_spread_mixed_directive,
      # %{"skip" => false}},
      {:fragment_spread_no_directive, @fragment_spread_no_directive, %{}},
      {:skip_false_inline_fragment, @skip_inline_fragment, %{"skip" => false}},
      {:skip_true_inline_fragment, @skip_inline_fragment, %{"skip" => true}},
      # {:skip_inline_fragment_mixed_directive, @skip_inline_fragment_mixed_directive,
      # %{"skip" => false}},
      {:inline_fragment_no_directive, @inline_fragment_no_directive, %{}},
      {:include_true_fragment_spread, @include_fragment_spread, %{"include" => true}},
      {:include_false_fragment_spread, @include_fragment_spread, %{"include" => false}},
      # {:include_fragment_spread_mixed_directive, @include_fragment_spread_mixed_directive,
      # %{"inline" => true}},
      {:include_true_inline_fragment, @include_inline_fragment, %{"include" => true}},
      {:include_false_inline_fragment, @include_inline_fragment, %{"include" => false}}
      # {:include_inline_fragment_mixed_directive, @include_inline_fragment_mixed_directive,
      # %{"inline" => true}}
    ]

    for {name, query, vars} <- queries do
      pre_pipeline = build_pre_pipeline(vars)
      post_pipeline = build_post_pipeline(vars)

      {:ok, partial, _} = Absinthe.Pipeline.run(query, pre_pipeline)

      # Ensure the pipeline was successful
      {:ok, result, _steps} = Absinthe.Pipeline.run(partial, post_pipeline)
      nil = get_in(result, [Access.key!(:result), :errors])

      {name, post_pipeline, partial}
    end
  end

  def build_pre_pipeline(variables) do
    variables
    |> build_pipeline()
    |> Absinthe.Pipeline.before(Absinthe.Phase.Document.Context)
  end

  def build_post_pipeline(variables) do
    variables
    |> build_pipeline()
    |> Absinthe.Pipeline.from(Absinthe.Phase.Document.Context)
  end

  def build_pipeline(variables) do
    AbsintheTestFragmentPerformanceWeb.Schema
    |> Absinthe.Pipeline.for_document(
      variables: variables,
      context: %{}
    )
    |> Absinthe.Pipeline.without(Absinthe.Phase.Telemetry)
  end

  def benchmarks do
    setup()
    |> Enum.into(%{}, fn {name, pipeline, query} ->
      {to_string(name),
       fn ->
         {:ok, _result, _steps} = Absinthe.Pipeline.run(query, pipeline)
       end}
    end)
  end
end

Benchee.run(FragmentBench.benchmarks(), memory_time: 2)

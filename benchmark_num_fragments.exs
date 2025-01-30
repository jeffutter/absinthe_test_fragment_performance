defmodule FragmentBench do
  def tests(steps) do
    max_fields = Enum.max(steps)

    # Simulate the query cache
    query_cache = :ets.new(:query_cache, [:public, read_concurrency: true])

    # for step <- steps, vars <- [%{"include" => true}, %{"include" => false}], into: %{} do
    for step <- steps, vars <- [%{"skip" => false}], into: %{} do
      AbsintheTestFragmentPerformance.SchemaBuilder.define_schema(step, max_fields)

      mod = AbsintheTestFragmentPerformance.SchemaBuilder.mod_name(step)

      test_name = "#{mod} #{step} #{inspect(vars)}"

      {test_name,
       {
         fn {query_cache, ets_key, pipeline} ->
           [{^ets_key, partial}] = :ets.lookup(query_cache, ets_key)
           {:ok, _result, _steps} = Absinthe.Pipeline.run(partial, pipeline)
         end,
         # before_scenario: fn {query_name, vars} ->
         before_scenario: fn query_name ->
           vars =
             if step == 0 do
               %{}
             else
               vars
             end

           query = apply(mod, query_name, [])

           pipeline =
             Absinthe.Pipeline.for_document(
               mod,
               variables: vars,
               context: %{}
             )
             |> Absinthe.Pipeline.without(Absinthe.Phase.Telemetry)

           # Run the pipeline up-to Document.Context before executing the profile
           # This simulates some caching we do in production where the blueprint
           # is cached here before applying variables
           pre_pipeline = Absinthe.Pipeline.before(pipeline, Absinthe.Phase.Document.Context)

           post_pipeline = Absinthe.Pipeline.from(pipeline, Absinthe.Phase.Document.Context)

           {:ok, partial, _} = Absinthe.Pipeline.run(query, pre_pipeline)
           ets_key = {mod, query_name, vars}
           :ets.insert(query_cache, {ets_key, partial})

           # Ensure the pipeline was successful
           {:ok, result, _steps} = Absinthe.Pipeline.run(partial, post_pipeline)
           nil = get_in(result, [Access.key!(:result), :errors])

           {query_cache, ets_key, post_pipeline}
         end
       }}
    end
  end
end

# steps = for i <- 0..100, n = i * i, n <= 100, do: n
steps = [0, 5, 10, 25, 50, 100]

IO.inspect(steps, label: "Steps")

# Doesn't seem to make a difference if fields are skipped or not
# I don't think skip vs include matters

Benchee.run(FragmentBench.tests(steps),
  inputs: %{
    "skip_spread" => :query_skip_spread
    # "include_spread" => :query_include_spread,
    # "skip_inline" => :query_skip_inline
    # "include_inline" => :query_include_inline
    # "skip_spread skip:true" => {:query_skip_spread, %{"skip" => true}},
    # "skip_spread skip:false" => {:query_skip_spread, %{"skip" => false}},
    # "include_spread include:true" => {:query_include_spread, %{"include" => true}},
    # "include_spread include:false" => {:query_include_spread, %{"include" => false}},
    # "skip_inline skip:true" => {:query_skip_inline, %{"skip" => true}},
    # "skip_inline skip:false" => {:query_skip_inline, %{"skip" => false}},
    # "include_inline include:true" => {:query_include_inline, %{"include" => true}},
    # "include_inline include:false" => {:query_include_inline, %{"include" => false}}
  },
  memory_time: 2,
  formatters: [
    # Benchee.Formatters.HTML,
    Benchee.Formatters.Console
  ],
  profile_after: {:tprof, [type: :memory, memory: 5000]}
)

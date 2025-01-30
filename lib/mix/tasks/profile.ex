defmodule Mix.Tasks.Profile do
  use Mix.Task

  def run(["dump_schema", fields]) do
    {fields, _} = Integer.parse(fields)
    ast = AbsintheTestFragmentPerformance.SchemaBuilder.build_schema(fields, fields)
    IO.puts(Macro.to_string(ast))
  end

  def run(["dump_query", query_name, fields]) do
    {fields, _} = Integer.parse(fields)
    mod = AbsintheTestFragmentPerformance.SchemaBuilder.define_schema(fields, fields)

    query =
      case query_name do
        "skip_spread" -> mod.query_skip_spread()
        "include_spread" -> mod.query_include_spread()
        "skip_inline" -> mod.query_skip_inline()
        "include_inline" -> mod.query_include_inline()
      end

    IO.puts(query)
  end

  def run([query_name, profiler, fields, times]) do
    {fields, _} = Integer.parse(fields)
    mod = AbsintheTestFragmentPerformance.SchemaBuilder.define_schema(fields, fields)

    query =
      case query_name do
        "skip_spread" -> mod.query_skip_spread()
        "include_spread" -> mod.query_include_spread()
        "skip_inline" -> mod.query_skip_inline()
        "include_inline" -> mod.query_include_inline()
      end

    :ok = Application.ensure_started(:tools)
    :ok = Application.ensure_started(:xmerl)
    {:ok, _} = Application.ensure_all_started(:absinthe_test_fragment_performance)

    variables =
      if fields == 0 do
        %{}
      else
        %{"skip" => false}
      end

    pipeline =
      Absinthe.Pipeline.for_document(mod,
        variables: variables,
        context: %{}
      )
      |> Absinthe.Pipeline.without(Absinthe.Phase.Telemetry)

    # Run the pipeline up-to Document.Context before executing the profile
    # This simulates some caching we do in production where the blueprint
    # is cached here before applying variables
    pre_pipeline =
      pipeline
      |> Absinthe.Pipeline.before(Absinthe.Phase.Document.Context)

    post_pipeline =
      pipeline
      |> Absinthe.Pipeline.from(Absinthe.Phase.Document.Context)

    {:ok, partial, _} = Absinthe.Pipeline.run(query, pre_pipeline)

    times = String.to_integer(times)

    # Warmup
    {:ok, result, _steps} = Absinthe.Pipeline.run(query, pipeline)

    # Ensure the pipeline was successful
    nil = get_in(result, [Access.key!(:result), :errors])

    :erlang.garbage_collect()

    with_profiler(profiler, fn ->
      IO.puts("Profile Start")

      for _ <- 0..(times - 1) do
        {:ok, _result, _steps} = Absinthe.Pipeline.run(partial, post_pipeline)
      end

      IO.puts("Profile Done")
    end)
  end

  def with_profiler("cprof", f) do
    :cprof.start()

    f.()

    {:ok, modules} = :application.get_key(:absinthe, :modules)

    Enum.map(modules, fn module ->
      :cprof.analyse(module)
    end)
    |> Enum.sort_by(fn {_, x, _} -> x end, :asc)
    |> IO.inspect(limit: :infinity)

    :cprof.stop()
  end

  def with_profiler("eprof", f) do
    :eprof.profile(f)

    :eprof.analyze()
  end

  def with_profiler("tprof", f) do
    :tprof.profile(f, %{type: :call_memory})
    # :tprof.profile(f, %{type: :call_count})
  end

  def with_profiler("eflambe", f) do
    # :eflambe.apply({f, []}, output_format: :svg)
    :eflambe.apply({f, []}, [])
  end

  def with_profiler("fprof", f) do
    :fprof.trace([:start, verbose: true, procs: [self()]])
    f.()
    :fprof.trace(:stop)
    :fprof.profile()
    :fprof.analyse({:dest, ~c"profile.fprof"})
  end
end

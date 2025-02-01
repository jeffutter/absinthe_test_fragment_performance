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
      case {fields, String.contains?(query_name, "skip"), String.contains?(query_name, "include")} do
        {0, _, _} -> %{}
        {_, true, _} -> %{"skip" => false}
        {_, _, true} -> %{"include" => true}
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

  def with_profiler("gc", f) do
    ref = make_ref()
    Process.flag(:trap_exit, true)
    start_runner(f, ref)

    await_results(nil, ref)
    |> IO.inspect()

    # Benchee.Benchmark.Collect.Memory.collect(f)
    # |> IO.inspect()

    # me = self()
    #
    # spawn(fn ->
    #   IO.inspect(:erlang.process_info(self(), :garbage_collection))
    #   IO.inspect(:erlang.process_info(self(), :garbage_collection_info))
    #   {:memory, before} = :erlang.process_info(self(), :memory)
    #   IO.inspect(:erlang.process_info(self(), :garbage_collection))
    #   IO.inspect(:erlang.process_info(self(), :garbage_collection_info))
    #
    #   f.()
    #
    #   IO.inspect(:erlang.process_info(self(), :garbage_collection))
    #   IO.inspect(:erlang.process_info(self(), :garbage_collection_info))
    #   {:memory, aft} = :erlang.process_info(self(), :memory)
    #
    #   :erlang.garbage_collect()
    #   IO.inspect(:erlang.process_info(self(), :garbage_collection))
    #   IO.inspect(:erlang.process_info(self(), :garbage_collection_info))
    #
    #   {:memory, aft_gc} = :erlang.process_info(self(), :memory)
    #
    #   IO.puts("Pipeline | Allocated: #{aft - before} | Churn: #{aft_gc - aft}")
    #   send(me, :done)
    # end)
    #
    # receive do
    #   :done -> :done
    # end
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

  defp await_results(_, ref) do
    receive do
      {^ref, stats} ->
        stats

      {^ref, :shutdown} ->
        nil

      # we need a really basic pattern here because sending anything other than
      # just what's returned from the function that we're benchmarking will
      # involve allocating a new term, which will skew the measurements.
      # We need to be very careful to always send the `ref` in every other
      # message to this process.
      new_result ->
        await_results(new_result, ref)
    end
  end

  defmodule GCStats do
    defstruct word_size: nil,
              memory: 0,
              minor_gc_count: 0,
              major_gc_count: 0,
              bin_vheap_size: 0,
              total_freed: 0,
              minor_freed: 0,
              major_freed: 0
  end

  defp start_runner(fun, ref) do
    parent = self()

    spawn_link(fn ->
      me = self()

      word_size = :erlang.system_info(:wordsize)
      tracer = spawn(fn -> tracer_loop(me, %GCStats{word_size: word_size}) end)

      _ = measure_memory(fun, tracer, parent)
      send(parent, {ref, get_collected_stats(tracer)})

      send(tracer, :done)
    end)
  end

  defp get_collected_stats(tracer) do
    ref = Process.monitor(tracer)
    send(tracer, {:get_collected_stats, self(), ref})

    receive do
      {:DOWN, ^ref, _, _, _} -> nil
      {^ref, collected} -> collected
    end
  end

  defp measure_memory(fun, tracer, parent) do
    :erlang.garbage_collect()
    send(tracer, :begin_collection)

    receive do
      :ready_to_begin -> nil
    end

    return_value = fun.()
    send(parent, return_value)

    :erlang.garbage_collect()
    send(tracer, :end_collection)

    receive do
      :ready_to_end -> nil
    end

    # We need to reference these variables after we end our collection so
    # these don't get GC'd and counted towards the memory usage of the function
    # we're benchmarking.
    {parent, fun}
  end

  defp tracer_loop(pid, acc) do
    receive do
      :begin_collection ->
        :erlang.trace(pid, true, [:garbage_collection, tracer: self()])
        send(pid, :ready_to_begin)
        tracer_loop(pid, acc)

      :end_collection ->
        :erlang.trace(pid, false, [:garbage_collection])
        send(pid, :ready_to_end)
        tracer_loop(pid, acc)

      {:get_collected_stats, reply_to, ref} ->
        send(reply_to, {ref, acc})

      {:trace, ^pid, :gc_minor_start, info} ->
        listen_gc_end(pid, :gc_minor_end, acc, info)

      {:trace, ^pid, :gc_major_start, info} ->
        listen_gc_end(pid, :gc_major_end, acc, info)

      :done ->
        exit(:normal)
    end
  end

  defp listen_gc_end(pid, tag, acc, start_info) do
    receive do
      {:trace, ^pid, ^tag, end_info} ->
        memory = (total_memory(start_info) - total_memory(end_info)) * acc.word_size

        heap_freed =
          Keyword.fetch!(start_info, :heap_size) -
            Keyword.fetch!(end_info, :heap_size)

        old_heap_freed =
          Keyword.fetch!(start_info, :old_heap_size) -
            Keyword.fetch!(end_info, :old_heap_size)

        freed = (heap_freed + old_heap_freed) * acc.word_size

        ## Also consider old_heap

        bin_vheap_size =
          (total_bin_vheap_size(start_info) -
             total_bin_vheap_size(end_info)) * acc.word_size

        case tag do
          :gc_minor_end ->
            tracer_loop(pid, %GCStats{
              acc
              | memory: acc.memory + memory,
                minor_gc_count: acc.minor_gc_count + 1,
                bin_vheap_size: acc.bin_vheap_size + bin_vheap_size,
                minor_freed: acc.minor_freed + freed,
                total_freed: acc.total_freed + freed
            })

          :gc_major_end ->
            tracer_loop(pid, %GCStats{
              acc
              | memory: acc.memory + memory,
                major_gc_count: acc.major_gc_count + 1,
                bin_vheap_size: acc.bin_vheap_size + bin_vheap_size,
                major_freed: acc.major_freed + freed,
                total_freed: acc.total_freed + freed
            })
        end
    end
  end

  defp total_memory(info) do
    Keyword.fetch!(info, :heap_size) + Keyword.fetch!(info, :old_heap_size)
  end

  defp total_bin_vheap_size(info) do
    Keyword.fetch!(info, :bin_vheap_size) + Keyword.fetch!(info, :bin_old_vheap_size)
  end
end

# AbsintheTestFragmentPerformance

## Things you can do!

### Run The Server

```
mix phx.server
```

### Run The Benchmark

Benchmark generated schemas and queries with various options for number of fragments and type of fragment.
```
mix run benchmark_num_fragments.exs
```

```
mix run benchmark.exs
```

### Profiles

Generate a schema of a given size and execute a profile against it.

Values for `query_name` options are:
- skip_spread
- include_spread
- skip_inline
- include_inline

#### See the schema for a given number of fragments

```
mix profile dump_schema <num fragments>
```

#### See the query for a given number of fragments
```
mix profile dump_query <query_name> <num fragments>
```

#### Execute a profile
```
mix profile <query_name> <profiler> <num fragments> <num times to run the query>
```

Values for `profiler` are:
- cprof
- eprof
- fprof
- tprof (on OTP-27)
- eflambe

[
  import_deps: [:ash_phoenix, :ash_postgres, :ash, :reactor, :phoenix],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"]
]

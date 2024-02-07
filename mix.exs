defmodule DV.MixProject do
  use Mix.Project

  def project do
    [
      app: :DV,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      compilers: if Mix.env() == :dev do [:unused] ++ Mix.compilers() else Mix.compilers() end,
      unused: [
        ignore: [
          {APIV1SocketHandler},
          {DV},
          {DataSources},
          {PlatformFuncs},
          {MariaDBFuncs},
          {LDAP},
          {AccessControl},
          {Parsec},
          {QP},
          {QueryHandler},
          {Metadata},
          {ResultSet},
          {ResultSet.FileResult},
          {ResultSet.WebAPIResult},
          {ResultSet.ODBCResult},
          {StandardODBCConnector},
          {WebAPIConnector},
          {FileConnector},
          {ForcePlatformFuncs},
          {PostgreSQLFuncs},
          {~r/String\.Chars/},
          {~r/Vex|Jason|DV\.Request/},
          {DVApp.Supervisor}
        ]
      ],
      deps: deps(),
      default_release: :prod,
      releases: [
        prod: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent]
        ]
      ],

      name: "Attrition Data Virtualization Platform",
      source_url: "https://github.com/attrition-dv/attrition-dv",
      homepage_url: "https://attrition.dev",
      docs: [
        output: "public",
        main: "getting_started",
        api_reference: false,
        extras: ["extra_docs/getting_started.md","extra_docs/data_sources.md","extra_docs/platform_api.md","extra_docs/sql_support.md"],
        before_closing_footer_tag: fn _formatter -> "Hosted by GitHub Pages (<a href=\"https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages#data-collection\">Privacy Policy</a>)" end
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      # TODO: standardize logging
      extra_applications: [:lager,:logger,:kerlberos,:odbc,:eldap],
      mod: {DVApp,[]}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mix_unused, "~> 0.3.0",only: :dev,runtime: false},
      {:ex_doc, "~> 0.31",only: :dev,runtime: false},
      {:makeup_json, "~> 0.1.0",only: :dev,runtime: false},
      {:mock, "~> 0.3.8",only: :test,runtime: false},
      {:temp, "~> 0.4",only: :test,runtime: false},
      # Required for Query Parser
      {:nimble_parsec, "~> 1.0"},
      # Required for Query Handler
      {:uuid, "~> 1.1"},
      # Required for Web Broker Plug
      {:bandit, "~> 1.1"},
      {:plug, "~> 1.14"},
      {:jason, "~> 1.4"},
      {:websock_adapter, "~> 0.5.4"},
      {:cors_plug, "~> 3.0"},
      # Required for SPNEGO
      # {:kerlberos, "~> 2.0.1"}, # /api endpoint authentication
      {:kerlberos,git: "https://github.com/vocalvogel/kerlberos.git",ref: "master"},
      {:sasl_auth, git: "https://github.com/starbelly/sasl_auth.git",ref: "fix-segfault-possibilities"}, # Web API data source SPNEGO authentiation
      # Required for default storage backend [CubDB]
      {:cubdb, "~> 2.0"},
      # Required for input validation
      {:vex, "~> 0.9.1"},
      # Required for flat file (CSV) data source support
      {:csv, "~> 3.2"},
      # Required for flat file (JSON) data source support
      {:jaxon, "~> 2.0"},
      # Required for Web API data source support
      {:req, "~> 0.4.0"},
      # Required for LDAP support (user privlieges by LDAP group, auto user creation by LDAP group)
      {:eldap_string_filters, "~> 0.1.2"}
    ]
  end
end

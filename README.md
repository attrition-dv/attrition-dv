# Attrition Data Virtualization Platform

A proof-of-concept data virtualization platform written in the [Elixir](https://elixir-lang.org/) programming language. Developed as part of a university capstone project.

The project primarily consists of Elixir-based middleware, providing the following features:

- Kerberos authentication for incoming (client API) and outgoing (data source connectivity) requests
- Custom SQL parser supporting a reduced subset of SQL statements and functions
- Connectivity to several common data source types, including ODBC databases, JSON REST APIs, and Flat Files (delimited, JSON)
- Preliminary function pushdown support for MariaDB and PostgreSQL

A proof-of-concept web UI is available at https://github.com/attrition-dv/attrition-ui . 

## License
Core platform is licensed under the Mozilla Public License and is incompatible with secondary licenses. Some dependencies use other license terms. See the LICENSE and NOTICE files for details.

## Documentation
Core platform documentation is available at [https://attrition.dev](https://attrition.dev) .

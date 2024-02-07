# Getting Started
## System Requirements
### Platform Server 

The platform server build environment requires a recent **Linux** * distribution with the following packages installed:

* Elixir 1.14+ (Erlang/OTP 25+)
* Cyrus SASL libraries (e.g. libsasl2-dev and libsasl2-2)
* Cyrus GSSAPI bindings for Kerberos (e.g. libsasl2-modules-gssapi-mit)
* Kerberos Development Libraries (e.g. krb5-devel krb5-client)
* A recent version of Make

\**The initial development and most extensive testing was performed on OpenSUSE Tumbleweed.*

### Supporting Infrastructure
In addition to the platform server requirements, full deployment of the platform requires the following additional infrastructure components:

* LDAP Server (_tested with **389 Directory Server version 2.3.0**_)
    * The LDAP server must allow anonymous queries
* Kerberos (_tested with **MIT Kerberos version 5 release 1.20.1**_)
    * Two Kerberos principals with keytabs (these can be the same principal if desired):
        * One for **incoming** Platform API calls via GSSAPI (Keytab with the platform service SPN)
        * One for **outgoing** Kerberos connectivity to data sources (Keytab for kinit as the client principal)

### Data Sources
Configure required Data Sources. See [Data Source Support](extra_docs/data_sources.md) for instructions.

## Install
### Before You Begin
 If upgrading from a previous version - **back up** the **config** folder first.

Depending on your intended deployment method, you may wish to do all of these steps as a separate user account reserved for running the Platform Server. 

### Download Platform Server Build Environment
1. Clone the latest version:`git clone https://gitlab.com/attrition/attrition-dv` 
2.  `cd attrition-dv;mix deps.get` to pull all dependencies

### Configure The Build
Using a text editor, edit `config/config.exs` and change the following settings (look for `config $section $setting`):

| Section      | Setting              | Description                                                                                                                | Allowed Values                                                                                            | Required?                                               |
|--------------|----------------------|:--------------------------------------------------------------------------------------------------------------------------:|-----------------------------------------------------------------------------------------------------------|---------------------------------------------------------|
|              |                      |                                                                                                                            |                                                                                                           |                                                         |
| `:cors_plug` | `:origin`            | Allowed Origins for Platform API requests (CORS headers)                                                                   | See [CorsPlug Documentation](https://hexdocs.pm/cors_plug/readme.html).                                   | Y                                                       |
| `:DV`        | `:metadata_base_dir` | Path to store platform metadata. Must exist, be owned by the ID which will run the Platform Server, and have appropriate permissions (e.g. `chmod 700`). | Linux folder path.                                                          | Y                                                       |
| `:DV`        | `:initial_admins`    | Initial admin users for the platform. Used on first start-up.                                                              | A list of LDAP users and groups, in the format of `[{:user,:ldap,$username},{:group,:ldap,$group_name}]`. | Y (initial run only)                                    |
| `:DV`        | `:ldap_server_hostname` | Hostname of LDAP Server |  Hostname | Y |
| `:DV`        | `:ldap_query_base` | Base component for LDAP lookups | LDAP search path (e.g. `dn=example,dn=com`) | Y | 
| `:DV`        | `:kerberos_server_keytab` | Kerberos Keytab file for **INCOMING** Kerberos requests. | Linux file path. | Y | 
| `:DV`        | `:kerberos_client_keytab` | Kerberos Keytab file for **OUTGOING** Kerberos requests. | Linux file path. | Y |
| `:DV`        | `:kerberos_client_uid` | User ID for the outgoing Kerberos keytab | username (should be the user principal name without the realm)| Y |                                                        |
| `:DV`        | `:connectors`        | Enabled data source connectors.                                                                                            | A list of enabled data source connectors and their associated support modules. See [Data Source Support](extra_docs/data_sources.md).                   |   Y |                                                     |
| `:DV`        | `:enable_http`       | Whether to enable HTTP (insecure) Platform API Requests.                                                                   | `true/false`                                                                                              | One or more of `:enable_http`/`:enable_https` required. |
| `:DV`        | `api_http_port`      | Port to listen on for HTTP (insecure) Platform API Requests.                                                               | Integer port (e.g. `4001`).                                                                               | If `:enable_http` is `true`.                            |
| `:DV`        | `:enable_https`      | Whether to enable HTTPS Platform API Requests. One or more of `:enable_http`/`:enable_https` required.                     | `true/false`                                                                                              | One or more of `:enable_http`/`:enable_https` required. |
| `:DV`        | `api_https_port`     | Port to listen on for HTTPS Platform API Requests.                                                                         | Integer port (e.g. `4101`).                                                                               | If `:enable_https` is `true`.                           |
| `:DV`        | `:https_certfile`    | Path to SSL Certificate (.pem format)                                                                                      | Linux file path.                                                                                          | If `:enable_https` is `true`.                           |
| `:DV`        | `:https_keyfile`     | Path to SSL Private Key (.pem format)                                                                                      | Linux file path. Must not have a password set.                                                            | If `:enable_https` is `true`.                           |
| `:DV`        | `:result_set_expiry` | Time (in minutes) to keep cached query results (default: 3 minutes) | Integer | N | 

### Build/Run The Platform Server
There are currently 3 options for running the Platform Server:

#### Run Directly From Source
*Most useful for running the Platform Server in an ad-hoc manner, or as part of a scripted deployment.*

1. `cd $repo_folder_name`
2. `mix run --no-halt`

#### Build Standalone Executable
*Most useful for running the Platform Server as a service (e.g. via systemctl), or for building one consistent executable to use on multiple servers.*

1. `cd $repo_folder_name`
2. `MIX_ENV=prod mix release --path $path_to_executable --force --overwrite` (where `$path_to_executable` is a new or empty path)
3. To run: `$path_to_executable/prod start`

#### Docker
While not tested as extensively as the other options, it is possible to deploy the Platform Server in a Docker container. General steps are as follows:

1. Make a new staging directory for the Docker prep
3. Copy the source to **app**
4. Copy both keytabs and the krb5.conf file to **etc**
5. Copy the required drivers into appropriate folders

In order to persist data between runs, ensure that `:metadata_base_dir` is mounted as a Docker volume. 

### Using The Platform
- The platform is accessible via [REST and WebSocket APIs](extra_docs/platform_api.md). 
- A rudimentary web based UI is [available here](https://gitlab.com/attrition/attrition-ui).

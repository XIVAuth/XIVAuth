<div align="center" style="text-align: center;">
<a href="https://xivauth.net"><img src="./app/assets/images/logos/xivauth-logo-45.svg" alt="XIVAuth Logo" width="250"/></a>
<br/>
<em>The last Lodestone code you'll ever need.</em>
<br/><br/>
</div>

[![Active User Count](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fxivauth.net%2Fpulse.json&query=%24.characters&label=verified%20characters)](#) 
[![GitHub branch status](https://img.shields.io/github/checks-status/xivauth/xivauth/main?label=ci)](#)
[![codecov](https://codecov.io/github/XIVAuth/XIVAuth/graph/badge.svg?token=VS3CZE2QQ2)](https://codecov.io/github/XIVAuth/XIVAuth)

---

XIVAuth is an identity provider designed to provide a unified, cohesive, and secure authentication solution for the 
community of the critically acclaimed MMORPG Final Fantasy XIV. Users can quickly and easily connect to many apps
across the ecosystem, and developers can implement a secure authentication process just as easily.

At a high level, XIVAuth allows users to create, register, and verify their characters with the service. Other sites or
services may then use an OAuth2-like flow (Discord-flavored SSO) to allow users to sign in with a user identity or one
(or more) of the player's character identities. Users only need to register their characters once to be able to use them
on any service that uses XIVAuth.

### Using XIVAuth

XIVAuth is hosted at [`https://xivauth.net/`](https://xivauth.net/) and is available for use by any user or developer.
Developers need to go through a brief onboarding process requiring both multifactor authentication and verifying 
ownership of a single character to prevent spam.

XIVAuth supports the following key features:

* A broad set of login strategies for user flexibility.
  * Discord, Steam, GitHub, and Twitch are supported for social login, with the ability to convert to a normal account.
  * MFA protection is provided via TOTP or passkeys, including passwordless login capability.
* OAuth2 identity services with a similar developer experience to Discord.
  * Support for Authorization Code, Device Code, and Client Credential flows for a wide variety of use cases.
* Character attestation services via JWT claims or X.509 certificates.
  * Claims may be verified both offline and online.
* Team management allows multiple developers to share application confirmations, with subteam support.
* Private apps only permitting a specific allowlist of users.
* A pettable catgirl.

XIVAuth does not provide full-fledged Lodestone scraping services (see [Flarestone][flarestone] for that), nor is it
intended to provide authorization or accounting services. In other words, if you are trying to build an app that only
Lalafell players may access, your app will still need to implement its own checks on the attested character. It is best
to consider XIVAuth as the equivalent of enterprise tools like Okta, Auth0, or Ping Identity for the FINAL FANTASY XIV
ecosystem. 

[flarestone]: https://github.com/xivauth/flarestone
[xivapi]: https://v2.xivapi.com/

### Running XIVAuth Locally

To run XIVAuth locally, you need Docker installed and properly configured and a `.env` file set up. A template 
`development.env` is provided and can just be copied over accordingly. To actually start the server, all that should be
necessary is the following command:

```shell
docker compose up
```

If this is your first time running the application, also initialize the database:

```sh
docker compose run app rake db:setup
```

This will create the database, load in the latest schema copy, and seed the database with some useful sample data. If
you plan on doing a lot of development work, you may consider creating a `private.rb` file in `db/seeds/development/` to
load any extra things you might want to include at initialization time.

If you prefer to run Rails without Docker, you can run the standard setup commands from the Ruby environment of your
choice. Please note that you will need to have Postgres and Redis installed and accessible to the app, with the
appropriate connection settings configured. See `development.env` for a more cohesive sample.

```sh
bundle install
bundle exec rake db:setup
bundle exec bin/dev
```

#### Local Credentials

XIVAuth's [development database seed](./db/seeds/development/development.rb) creates an admin user with credentials 
`dev@eorzea.id` with a password of `password`. This should be enough to get started with base development. You will be
able to perform nearly any action inside the platform and should be able to register characters directly.

Certain XIVAuth features (particularly social login and mailer testing) require the use of an encrypted credentials
file. A sample file and instructions are present in `config/credentials/sample.yml`. Note that setting up credentials
is *not* required for standard development. If credentials are not provided, XIVAuth will fall back to default values
or generate new ones.

Certain data values (such as character persistent keys, verification codes, and other sensitive information) are
dynamically generated using Rails' [Secret Key Base][secret-key-base]. In local development environments, Rails will
automatically generate a key for you and store it in `tmp/local_secret.txt`. If you would like to override this key, you
may set the `SECRET_KEY_BASE` environment variable, change the value of `tmp/local_secret.txt`, or add a 
`secret_key_base` to your development credentials file. This value is safe to share between developer environments, but
new keys should always be generated for a production deployment. 

[secret-key-base]: https://rubydoc.info/docs/rails/Rails%2FApplication:secret_key_base
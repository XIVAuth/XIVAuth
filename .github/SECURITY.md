# XIVAuth Security Policy

> The most up to date version of this security policy is available at https://xivauth.net/legal/security. That document
> will supersede this one in cases of disagreement. This document also includes important information that may not be
> present in this document, such as pentesting ground rules for certain environments.


## Reporting Security Issues

Please report security issues by sending an email to [`security@xivauth.net`](mailto:security@xivauth.net) or by
sending a Discord direct message to `kazwolfe`. Please ensure that all security reports include detailed steps for
reproduction as well as both expected and observed behavior.

If your security report contains confidential or sensitive information, please encrypt your report with the PGP key
[`2588 13F5 3A16 EBB4`][pgpkey]. Please note that the email on this key will not match the above email. This key is
additionally available on other keyservers, as well as on [KazWolfe's GitHub][pgpkey-gh].

Please do not disclose any security vulnerability publicly until we have confirmed that the bug has been fixed. Under
certain rare cases, we may ask that you not publicly disclose a bug - we will provide specific justification to you if
this is the case.

[pgpkey]: https://keys.openpgp.org/vks/v1/by-fingerprint/14C529AD4BACE342F2E1AA5D258813F53A16EBB4
[pgpkey-gh]: https://github.com/KazWolfe.gpg

## Out of Scope Issues

The following systems may not be tested:

* Any underlying infrastructure, e.g. the servers running XIVAuth itself.
* Any of our providers, e.g. captcha bypasses via click farms.

The following security issues are considered "out of scope":

* Any attacks that rely on social engineering, including leaked or stolen credentials. 
* Any attacks that rely on physical or virtual access to a victim's computer or network.
* Any reports of publicly accessible XIVAuth API Keys.
* Any CSRF issues that do not modify state (e.g. logout commands).
* Any attacks that require the use of brute force, denial of service attacks, or similar.
* Any security issues in a specific API client (e.g. a plugin or web service).
* Any of the following without demonstrable widespread or significant impact:
  * Any plain text reflection, including non-persistent self-XSS.
  * Any missing or invalid HTTP headers or settings.
  * Anything related to CORS.
  * SPF, DMARC, or DKIM misconfigurations.
  * Attacks that rely on a specific browser or system configuration.

If your report covers one of the above categories and is a code-level issue, we encourage you to submit a normal 
[GitHub Issue][gh-issues] for it instead. 

[gh-issues]: https://github.com/XIVAuth/XIVAuth/issues

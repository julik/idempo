# Contributing to Idempo

Contributions are welcome! Please take a moment to review this document so that
contributing stays easy and effective for everyone involved.

I'd especially love to get:

* Reproductions of races and double execution - ideally as a deterministic spec
* Fixes from people running a backend in production (PGBouncer, MySQL proxies, SQLite under load)
* Documentation fixes

## What do I need to know to help?

If you would like to learn more about the technologies Idempo builds on, check out the (non-exhaustive) list below. You can also get in touch with me via an issue or email.

 - [ruby](https://ruby-doc.org) and the [Rack specification](https://github.com/rack/rack/blob/main/SPEC.rdoc)
 - [Designing robust and predictable APIs with idempotency](https://stripe.com/blog/idempotency) by Brandur Leach - why idempotency keys exist at all
 - [Implementing Stripe-like Idempotency Keys in Postgres](https://brandur.org/idempotency-keys) and [Using Atomic Transactions to Power an Idempotent API](https://brandur.org/http-transactions), also by Brandur - how to build them on a database
 - [The Idempotency-Key HTTP Header Field](https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/), the IETF draft Idempo follows for the header (the draft has since expired)
 - Advisory locks in [PostgreSQL](https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS) and [MySQL](https://dev.mysql.com/doc/refman/8.4/en/locking-functions.html), and [UPSERT in SQLite](https://www.sqlite.org/lang_upsert.html), which the `TokenLock` is built on
 - [rspec](https://rspec.info) for testing

## Issues and pull requests

* Opening an issue first is often the fastest way to get something in. I can shape it into something that fits the library.
* The most useful bug report for a race is the exact order of events across requests, or better yet a spec which forces that order (with `Queue`s or fibers) instead of hoping for it with `sleep`.
* I may close a PR and implement the idea differently. That's not a rejection of the idea, and you'll be credited (`Co-authored-by`).
* Feel free to propose opinionated changes, but be prepared that your opinion won't be shared. It is a give-and-take.

## Code changes

Please adhere to the coding conventions used throughout the project (indentation,
accurate and terse comments, etc.) and any other requirements (such as test coverage).
Idempo supports Ruby 2.7 and newer, and Rack 2 and 3 - please don't use syntax or APIs
which rule either of those out.

Run `bundle exec rake standard` to make sure the code is properly formatted. The tests come in two parts:

* `bundle exec rake spec:standalone` needs no database server - the middleware, the memory and SQLite backends and the install generator. Set `BUNDLE_WITHOUT=db_servers` to skip installing the database clients, and `RACK_VERSION="~> 2.0"` to test against Rack 2.
* `bundle exec rake spec:mysql`, `spec:postgres` and `spec:redis` need the respective server running locally. `spec:servers` runs all three.

## Basic expectations

This project is something created with love, and I - as an author - expect you, as a contributor, to return the favor. The ground rules:

* Do your best to be kind.
* Be polite and direct. No abrasiveness, no passive-aggression.
* [Low-context](https://www.ebsco.com/research-starters/communication-and-mass-media/high-context-and-low-context-cultures) communication is preferred and permitted
* No ad-hominems, also in code comments
* No sexualized or aggressive language

As a maintainer, I reserve the right to deny any contribution, discussion post, comment or pull request I find inappropriate.

Similarly, I reserve the right to not accept any contribution that doesn't fit the goals or spirit of the project (or my own), without explaining why it has been refused.

## Decisions are final

You're welcome to make your case once, clearly. After that, please don't reopen closed issues, start meta-threads about the decision, or argue about the wording of this document. This is a list of expectations, not a contract to be lawyered. If something isn't covered, the maintainer's judgment applies.

## What happens elsewhere stays elsewhere

Contributions are judged on what they are, not on who sent them. What anyone says or does outside this project (on social media, at their job, in other repos, in politics) is not a topic here and will not be considered, either for or against them. Please don't bring it in: no call-outs, no "are you aware this person…" threads, no requests to ban someone over things that didn't happen here.

## AI-generated issues and code

This project uses LLMs to produce code and artifacts, and it's fine if you do the same when contributing. LLM use in this project is settled: threads about whether it should be used (utility, harm, societal implications etc.) will be closed.

Please disclose LLM use in every issue and PR: say which model or tool you used and what for (e.g. "Claude wrote the fix, I wrote the test"). This is for transparency, not for judgment. Disclosed LLM use is treated the same as no LLM use.

However, the following is on you:

* Make your LLM output _terse._ Nobody likes reading slop, even my agents. Make it get to the point.
* Make sure what you submit actually ran. Don't file issues about behavior or APIs your LLM imagined.
* Do not add external dependencies (or have your LLM do it) unless absolutely necessary
* If you file a PR, make at least one pass with "Make this at least 50% less code"
* Code generated by your LLM will be considered as written by you, with the same requirements

## License

By submitting a patch, you agree to allow the project owner to license your work under the same license as that used by the project, which you can see [here](LICENSE.txt).

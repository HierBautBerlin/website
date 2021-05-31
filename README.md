# Hier Baut Berlin

A tool to visualize and inform citizens of Berlin about governmental decisions.

[![Build Status](https://github.com/hierbautberlin/website/actions/workflows/elixir.yml/badge.svg?branch=main)](https://github.com/HierBautBerlin/website/actions/workflows/elixir.yml)

**You want to help?** Awesome. Scroll through the issues, open a new one, or just send
a short notice to [mail@hierbautberlin.de](mailto:mail@hierbautberlin.de). We are happy about every person who wants to help.

## Development setup

HierBautBerlin uses Elixir and Phoenix. Information on how
to install Elixir can be found [here](http://elixir-lang.org/install.html).

As database it uses [PostgreSQL](http://postgresql.org).

After you installed everything, the setup is as follows:

```bash
make update
make setup
make start
```

Before you contribute code, please make sure to read the [CONTRIBUTING.md](CONTRIBUTING.md)

This project is using [yarn](http://yarnjs.com/) for javascript dependency management.

## How to run the test suite

```bash
make check
```

You can also run the `ExUnit` tests in watch mode with:

```bash
make run-tests
```

## Deployment

The server is configured using [ansible](https://www.ansible.com/) with [this playbook](/ansible/playbook.yml) and can be updated with:

```bash
ansible-playbook ansible/playbook.yml -i ansible/hosts --extra-vars '{"username": "***********"}'
```

Deploy is done by running:

```bash
VERSION=`git rev-parse HEAD`
make prod-build
scp build/hierbautberlin-$VERSION.tar.gz user@server:~/hierbautberlin
ssh user@server 'bash -s' < bin/deploy.sh $VERSION
```

## Funding

This project is funded by the [German Federal Ministry of Education and Research](http://bmbf.de)
and is part of the 9th batch of the [prototype fund](http://prototypefund.de).

![Logo of the German Federal Ministry of Education and Research](images/support-bmbf.png)
![Prototype Fund Logo](images/support-prototype.png)

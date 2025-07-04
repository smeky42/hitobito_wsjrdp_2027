# Hitobito Wsjrdp 2027
This hitobito wagon is the registration for the [German Contingent](https://www.worldscoutjamboree.de).

## Setup Dev Environment
It is basically the [hitobito dev setup](https://github.com/hitobito/development/blob/master/doc/setup.md).
And in addition the [wagon creation for hitobito](https://github.com/puzzle/wagons).

```bash
# create hitobito development environment
mkdir WSJ2027Anmeldung
cd WSJ2027Anmeldung
git clone https://github.com/hitobito/development.git

# clone hitobito core and wsjrdp_2027 wagon
cd development/app
git clone https://github.com/hitobito/hitobito.git
git clone git@github.com:smeky42/hitobito_wsjrdp_2027.git
cd ..

# OR create a new wagon if you want to start bare
cd development/app/hitobito
rails generate wagon wsjrdp_2027
mkdir ../hitobito_wsjrdp_2027
mv vendor/wagons/wsjrdp_2027/* ../hitobito_wsjrdp_2027
cd ../..

# add docker volumes
docker volume create hitobito_bundle
docker volume create hitobito_yarn_cache

# start docker in hit environment
./bin/dev-env.sh
> hit up
```

If needed (as it was in my MacOS env)
    - add `export RAILS_UID=$(id -u)` to `.bashrc`
    - [install new ruby version](https://mac.install.guide/faq/change-ruby-version/) and [configure your shell env](https://mac.install.guide/ruby/13)
    - install `brew install postgresql` and run `brew services start postgresql@14`  postgress

On an ARM macOS with Docker desktop you might need to set
`DOCKER_DEFAULT_PLATFORM`, e.g., you might need to start `dev-env.sh`
like so:
```sh
RAILS_UID=$(id -u) DOCKER_DEFAULT_PLATFORM=linux/amd64 ./bin/dev-env.sh
```

This hitobito wagon defines the organization hierarchy with groups and roles
of Wsjrdp 2027.

## Wsjrdp 2027 Organization Hierarchy

<!-- roles:start -->

(Output of rake app:hitobito:roles)
<!-- roles:end -->

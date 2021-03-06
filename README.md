# Aker - Work App

[![Build Status](https://travis-ci.org/sanger/aker-work-app.svg?branch=devel)](https://travis-ci.org/sanger/aker-work-app)
[![Maintainability](https://api.codeclimate.com/v1/badges/d2721eface0c9cc74bb6/maintainability)](https://codeclimate.com/github/sanger/aker-work-app/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/d2721eface0c9cc74bb6/test_coverage)](https://codeclimate.com/github/sanger/aker-work-app/test_coverage)

This application allows users to create and manage work orders.

# Setup
## Database
To create the databases for your local environment: `bundle exec rails db:setup`

## JavaScript
Use Yarn to install the required Node modules: `bundle exec rails yarn:install`

## Broker
To create the exchanges, queues and usernames etc. use the GitLab repo: [aker-environments](https://gitlab.internal.sanger.ac.uk/aker/aker-environments)

## Foreman
There is a Procfile which should allow you to run the project with `foreman start`.

I had to jump through the following hoops:

* Using correct node version

        brew install nvm
        nvm ls-remote --lts # list versions with long-term support
        nvm install 8.15.0 # or whatever version
  The `.nvmrc` specifies what version the application will run with.

* Getting dependencies

        yarn install
        yarn upgrade
  I got warnings about missing dependencies related to `webpack-dev-server`. I ended up downgrading it to version 2 (specified in `package.json`).

* webpack port

    I changed `config/webpacker` to specify port 3036 instead of 3035, so it wouldn't try to use the same port as the set shaper.

# Testing
## Rspec
To run the rspec tests: `bundle exec rspec`

## JavaScript
To run JavaScript tests: `yarn test`

## Messages
The following messages are useful during testing:

* [Product catalogue schema](https://ssg-confluence.internal.sanger.ac.uk/display/PSDPUB/Product+Catalogue+JSON)
* [Product catalogue messages](https://ssg-confluence.internal.sanger.ac.uk/display/PSDPUB/Messages#Messages-Productcataloguemessages)
* [Work order messages](https://ssg-confluence.internal.sanger.ac.uk/display/PSDPUB/Messages#Messages-Workordermessages)

# Updates
## Gems
Run `bundle update` followed by `bundle exec rspec` to have the latest gems included in the project
and make sure that they behave as expected.

# Node packages
Run `yarn upgrade` follow by `yarn test`  to have the latest node packages included in the project
and make sure that they behave as expected.
# Misc.
## Assets
Assets are now compiled on the environments and do not need to be committed with the project
anymore.

## Work Order Dispatch
Work Orders are dispatched through the use of a job queue provided by the [Que gem](https://github.com/chanks/que). Jobs are not removed from the queue after they have been processed. Instead, they are marked as finished and kept in the database. If dispatch fails, jobs are added back to the queue for processing at a later time (config options to customise in `application.rb`).

You can get some basic stats on the queue using `Que.job_stats`.

There is also a QueJob model with a number of scopes available to look at jobs more closely:

  - `QueJob.errored`
  - `QueJob.not_errored`
  - `QueJob.expired`
  - `QueJob.not_expired`
  - `QueJob.finished`
  - `QueJob.not_finished`
  - `QueJob.scheduled`
  - `QueJob.not_scheduled`
  - `QueJob.ready`
  - `QueJob.not_ready`

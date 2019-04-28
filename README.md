# NanoTwitter: Timeline Data

This microservice is responsible for keeping track of the tweet IDs that make up every user's timeline, and injecting new tweets into timelines at the appropriate positions.

Production deployment: https://nano-twitter-timeline-data.herokuapp.com/

[![Codeship Status for cosi105/timeline_data](https://app.codeship.com/projects/696c2fd0-4c17-0137-d772-0a018d266758/status?branch=master)](https://app.codeship.com/projects/338763)
[![Maintainability](https://api.codeclimate.com/v1/badges/684bc84fd01743745a03/maintainability)](https://codeclimate.com/github/cosi105/timeline_data/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/684bc84fd01743745a03/test_coverage)](https://codeclimate.com/github/cosi105/timeline_data/test_coverage)

## Subscribed Queues

### new\_tweet.follower\_ids

- tweet_id
- follower_ids

### new\_follow.timeline\_data

- follower_id
- tweet_ids

## Published Queues

### new\_tweet.sorted\_tweets

- user_id
- sorted\_tweet\_ids

## Caches

### user\_id: sorted\_tweet\_ids
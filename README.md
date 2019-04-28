# NanoTwitter: Timeline Data

This microservice is responsible for keeping track of the tweet IDs that make up every user's timeline, and injecting new tweets into timelines at the appropriate positions.

Production deployment: https://nano-twitter-timeline-data.herokuapp.com/

[![Codeship Status for cosi105/timeline_data](https://app.codeship.com/projects/696c2fd0-4c17-0137-d772-0a018d266758/status?branch=master)](https://app.codeship.com/projects/338763)
[![Maintainability](https://api.codeclimate.com/v1/badges/684bc84fd01743745a03/maintainability)](https://codeclimate.com/github/cosi105/timeline_data/maintainability)
[![Test Coverage](https://api.codeclimate.com/v1/badges/684bc84fd01743745a03/test_coverage)](https://codeclimate.com/github/cosi105/timeline_data/test_coverage)

## Message Queues

| Relation | Queue Name | Payload | Interaction |
| :------- | :--------- | :------ |:--
| Subscribes to | `new_tweet.follower_ids` | `{tweet_id, follower_ids }` | Adds the given tweet ID to the timeline of every user in `follower_ids`, as happens when a user with many followers posts a tweet.
| Subscribes to | `new_follow.timeline_data` | `{follower_id, tweet_ids}` | Adds all of the given tweet IDs to the timeline of the user whose ID is `follower_id`, as happens when a user follows a person who has posted many tweets.
| Publishes to | `new_tweet.sorted_tweets` | `{user_id, sorted_tweet_ids}` | Publishes every timeline that has just been modified, so the Timeline HTML service can update.


## Caches

### user\_id: sorted\_tweet\_ids

## Seeding

This service subscribes to the `tweet.data.seed` queue, which the main NanoTwitter app uses to publish maps of users to the IDs of tweets in their timelines, enabling this service to build its cache.
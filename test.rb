# This file is a DRY way to set all of the requirements
# that our tests will need, as well as a before statement
# that purges the database and creates fixtures before every test

ENV['APP_ENV'] = 'test'
require 'simplecov'
SimpleCov.start
require 'minitest/autorun'
require './app'
require 'pry-byebug'

def app
  Sinatra::Application
end

def get_timeline(owner_id)
  REDIS.zrange(owner_id, 0, -1)
end

def publish_new_tweet(payload)
  RABBIT_EXCHANGE.publish(payload, routing_key: 'new_tweet.follower_ids')
  sleep 3
end

def publish_new_follow(payload)
  RABBIT_EXCHANGE.publish(payload, routing_key: 'new_follow.timeline_data')
  sleep 3
end

describe 'NanoTwitter Timeline Data' do
  include Rack::Test::Methods
  before do
    REDIS.flushall
  end

  it "can put a new tweet in a user's timeline" do
    payload = {
      tweet_id: 1,
      follower_ids: [2]
    }.to_json
    fanout_to_timelines(JSON.parse(payload))
    REDIS.keys.must_equal ['2']
    get_timeline(2).must_equal ['1']
  end

  it "can put a new tweet in a user's timeline from queue" do
    payload = {
      tweet_id: 1,
      follower_ids: [2]
    }.to_json
    publish_new_tweet(payload)
    REDIS.keys.must_equal ['2']
    get_timeline(2).must_equal ['1']
  end

  it 'can add many new tweets' do
    payload = {
      follow_params: {
        follower_id: 2
      },
      followee_tweet_ids: [2, 1, 3]
    }.to_json
    merge_into_timeline(JSON.parse(payload))
    REDIS.keys.must_equal ['2']
    get_timeline(2).must_equal %w[1 2 3]
  end

  it 'can add many new tweets from queue' do
    payload = {
      follow_params: {
        follower_id: 2
      },
      followee_tweet_ids: [2, 1, 3]
    }.to_json
    publish_new_follow(payload)
    REDIS.keys.must_equal ['2']
    get_timeline(2).must_equal %w[1 2 3]
  end

  it 'can seed many timelines' do
    [
      {
        owner_id: 2,
        sorted_tweets: [1, 2, 3].map { |i| { tweet_id: i } }
      }, {
        owner_id: 3,
        sorted_tweets: [4, 6, 7, 8].map { |i| { tweet_id: i } }
      }
    ].each { |timeline| seed_to_timelines(JSON.parse(timeline.to_json)) }
    REDIS.keys.sort.must_equal %w[2 3]
    get_timeline(2).must_equal %w[1 2 3]
    get_timeline(3).must_equal %w[4 6 7 8]
  end

  it 'can seed many timelines from queue' do
    [
      {
        owner_id: 2,
        sorted_tweets: [1, 2, 3].map { |i| { tweet_id: i } }
      }, {
        owner_id: 3,
        sorted_tweets: [4, 6, 7, 8].map { |i| { tweet_id: i } }
      }
    ].each { |timeline| RABBIT_EXCHANGE.publish(timeline.to_json, routing_key: 'timeline.data.seed.timeline_data') }
    sleep 10
    REDIS.keys.sort.must_equal %w[2 3]
    get_timeline(2).must_equal %w[1 2 3]
    get_timeline(3).must_equal %w[4 6 7 8]
  end
end

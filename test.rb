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
  get_shard(owner_id).zrange(owner_id, 0, -1)
end

def publish_new_tweet(payload)
  RABBIT_EXCHANGE.publish(payload, routing_key: 'new_tweet.follower_ids.timeline_data')
  sleep 3
end

def publish_new_follow(payload)
  RABBIT_EXCHANGE.publish(payload, routing_key: 'new_follow.timeline_data')
  sleep 3
end

describe 'NanoTwitter Timeline Data' do
  include Rack::Test::Methods
  before do
    SHARDS.each(&:flushall)
  end

  it "can put a new tweet in a user's timeline" do
    payload = {
      tweet_id: 1,
      follower_ids: [2]
    }.to_json
    fanout_to_timelines(JSON.parse(payload))
    SHARDS[2].keys.must_equal ['2']
    get_timeline(2).must_equal ['1']
  end

  it "can put a new tweet in a user's timeline from queue" do
    payload = {
      tweet_id: 1,
      follower_ids: [2]
    }.to_json
    publish_new_tweet(payload)
    SHARDS[2].keys.must_equal ['2']
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
    SHARDS[2].keys.must_equal ['2']
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
    SHARDS[2].keys.must_equal ['2']
    get_timeline(2).must_equal %w[1 2 3]
  end

  it 'can get a second page of a timeline' do
    payload = {
      follow_params: {
        follower_id: 2
      },
      followee_tweet_ids: [1, 2, 3, 4]
    }.to_json
    merge_into_timeline(JSON.parse(payload))
    resp = (get '/timeline?user_id=2&page_num=2&page_size=2').body
    JSON.parse(resp).must_equal %w[3 4]
  end

  it 'can seed data from CSV' do
    data = [[1, 1, 2, 3], [2, 1, 3]]
    CSV.open('temp.csv', 'wb') { |csv| data.each { |row| csv << row}}
    post '/seed', csv_url: './temp.csv'
    File.delete('temp.csv')
    get_shard(1).zrange(1, 0, -1).must_equal %w[1 2 3]
    get_shard(2).zrange(2, 0, -1).must_equal %w[1 3]
  end
end

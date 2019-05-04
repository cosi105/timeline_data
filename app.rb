# TimelineData Micro-Service (port 8082)
# Caches:
#   - TimelineData (port 6386)

require 'bundler'
require 'json'
Bundler.require
require './cache_seeder'

set :port, 8082 unless Sinatra::Base.production?

def redis_from_uri(key)
  uri = URI.parse(ENV[key])
  Redis.new(host: uri.host, port: uri.port, password: uri.password)
end

if Sinatra::Base.production?
  configure do
    SHARDS = [0, 1, 2, 3].map { |i| redis_from_uri("REDIS_#{i}_URL") }
  end
  rabbit = Bunny.new(ENV['CLOUDAMQP_URL'])
else
  SHARDS = [6386, 6388, 6389, 6390].map { |i| Redis.new(port: i) }
  rabbit = Bunny.new(automatically_recover: false)
end

rabbit.start
channel = rabbit.create_channel
RABBIT_EXCHANGE = channel.default_exchange

follower_ids = channel.queue('new_tweet.follower_ids.timeline_data')
new_follow_timeline_data = channel.queue('new_follow.timeline_data')
cache_purge = channel.queue('cache.purge.timeline_data')
SORTED_TWEETS = channel.queue('new_follow.sorted_tweets')

cache_purge.subscribe(block: false) { SHARDS.each(&:flushall) }

# Takes a new Tweet's follower_ids payload and updates its followers' cached Timeline Tweet IDs.
follower_ids.subscribe(block: false) do |delivery_info, properties, body|
  fanout_to_timelines(JSON.parse(body))
end

new_follow_timeline_data.subscribe(block: false) do |delivery_info, properties, body|
  merge_into_timeline(JSON.parse(body))
end

def get_shard(owner_id)
  SHARDS[owner_id % 4]
end

# Adds a new Tweet's ID to each follower's Timeline Tweet IDs in Redis.
def fanout_to_timelines(body)
  tweet_id = body['tweet_id'].to_i
  body['follower_ids'].each do |follower_id|
    get_shard(follower_id.to_i).zadd(follower_id.to_i, tweet_id, tweet_id) # 1st tweet_id param is set entry's sorting "score."
  end
end

# Adds new followee's Tweets to follower's Timeline Tweet IDs in Redis.
def merge_into_timeline(body)
  follower_id = body['follow_params']['follower_id'].to_i
  tweet_entries = body['followee_tweet_ids'].map(&:to_i)
  shard = get_shard(follower_id)

  if body['follow_params']['remove']
    shard.zrem(follower_id, tweet_entries) # Bulk remove from sorted set
  else
    shard.zadd(follower_id, tweet_entries.map { |tweet_id| [tweet_id, tweet_id] }) # Bulk add to sorted set
  end

  payload = {
    follower_id: follower_id,
    sorted_tweet_ids: shard.zrange(follower_id, 0, -1)
  }.to_json
  RABBIT_EXCHANGE.publish(payload, routing_key: SORTED_TWEETS.name)
end

get '/timeline' do
  user_id = params[:user_id].to_i
  page_num = params[:page_num].to_i
  page_size = params[:page_size].to_i

  start = page_size * (page_num - 1)
  finish = page_size * page_num
  get_shard(user_id).zrange(user_id, start, finish - 1).to_json
end

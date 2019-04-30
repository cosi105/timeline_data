# TimelineData Micro-Service (port 8082)
# Caches:
#   - TimelineData (port 6386)

require 'bundler'
require 'json'
Bundler.require

set :port, 8082 unless Sinatra::Base.production?

if Sinatra::Base.production?
  configure do
    redis_uri = URI.parse(ENV['REDIS_URL'])
    REDIS = Redis.new(host: redis_uri.host, port: redis_uri.port, password: redis_uri.password)
  end
  rabbit = Bunny.new(ENV['CLOUDAMQP_URL'])
else
  REDIS = Redis.new(port: 6386)
  rabbit = Bunny.new(automatically_recover: false)
end

rabbit.start
channel = rabbit.create_channel
RABBIT_EXCHANGE = channel.default_exchange

follower_ids = channel.queue('new_tweet.follower_ids')
new_follow_timeline_data = channel.queue('new_follow.timeline_data')
seed = channel.queue('timeline.data.seed.timeline_data')

seed.subscribe(block: false) do |delivery_info, properties, body|
  REDIS.flushall
  seed_to_timelines(JSON.parse(body))
end

# Takes a new Tweet's follower_ids payload and updates its followers' cached Timeline Tweet IDs.
follower_ids.subscribe(block: false) do |delivery_info, properties, body|
  fanout_to_timelines(JSON.parse(body))
end

new_follow_timeline_data.subscribe(block: false) do |delivery_info, properties, body|
  merge_into_timeline(JSON.parse(body))
end

def seed_to_timelines(body)
  owner_id = body['owner_id'].to_i
  unless owner_id == -1
    sorted_tweet_ids = body['sorted_tweets'].map { |t| t['tweet_id'].to_i }
    sorted_tweet_ids.each { |i| REDIS.zadd(owner_id.to_i, i, i) }
    puts "Seeded timeline for user #{owner_id}"
  end
end

# Adds a new Tweet's ID to each follower's Timeline Tweet IDs in Redis.
def fanout_to_timelines(body)
  tweet_id = body['tweet_id'].to_i
  body['follower_ids'].each do |follower_id|
    REDIS.zadd(follower_id.to_i, tweet_id, tweet_id) # 1st tweet_id param is set entry's sorting "score."
  end
end

# Adds new followee's Tweets to follower's imeline Tweet IDs in Redis.
def merge_into_timeline(body)
  follower_id = body['follow_params']['follower_id'].to_i
  tweet_entries = body['followee_tweet_ids'].map(&:to_i).map { |tweet_id| [tweet_id, tweet_id] } # Tweet_id as sorting "score" preserves chronology
  REDIS.zadd(follower_id, tweet_entries) # Bulk add
  payload = {
    follower_id: follower_id,
    sorted_tweet_ids: REDIS.zrange(follower_id, 0, -1)
  }.to_json
  RABBIT_EXCHANGE.publish(payload, routing_key: 'new_follow.sorted_tweets')
end

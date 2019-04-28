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
  Dotenv.load 'local_vars.env'
  REDIS = Redis.new
  rabbit = Bunny.new(automatically_recover: false)
end

rabbit.start
channel = rabbit.create_channel

follower_ids = channel.queue('new_tweet.follower_ids')

# Takes a new Tweet's follower_ids payload and updates its followers' cached Timeline Tweet IDs.
follower_ids.subscribe(block: false) do |delivery_info, properties, body|
  fanout_to_timelines(JSON.parse(body))
end

# Adds a new Tweet's ID to each follower's Timeline Tweet IDs in Redis.
def fanout_to_timelines(body)
  tweet_id = body['tweet_id'].to_i
  body['follower_ids'].each do |follower_id|
    REDIS.zadd(follower_id, tweet_id, tweet_id) # 1st tweet_id param is set entry's sorting "score."
  end
end

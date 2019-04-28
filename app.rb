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
html_fanout = channel.queue('new_tweet.html_fanout')

# Takes a new Tweet's html payload and updates its followers' cached Timeline HTML.
html_fanout.subscribe(block: false) do |delivery_info, properties, body|
  fanout_html(JSON.parse(body))
end

# Prepend the new Tweet's HTML to each follower's cached Timeline HTML.
def fanout_html(body)
  tweet_html = body['tweet_html']
  body['follower_ids'].each do |id|
    timeline_html = REDIS.get(id.to_i)
    REDIS.set(id.to_i, tweet_html + timeline_html)
  end
end

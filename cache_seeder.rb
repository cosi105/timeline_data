require 'csv'
require 'open-uri'
post '/seed' do
  puts 'Seeding all caches...'
  SHARDS.each(&:flushall)
  whole_csv = CSV.read(open(params[:csv_url]))
  whole_csv.each do |line|
    key = line[0]
    values = line.map { |a| [a.to_i, a.to_i] }
    get_shard(key.to_i).zadd(key, values)
  end
  puts 'Seeded all caches!'
end

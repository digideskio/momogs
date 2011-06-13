#!/usr/bin/env ruby
require 'rubygems'
require 'json'
require 'pp'
require 'date'
require 'time'
require 'mongo'
 
if ARGV.length < 7
  puts "usage: #{$0} yyyy mm dd yyyy mmm dd #numtopics"
  exit
end

metrics_start = Time.utc(ARGV[0], ARGV[1], ARGV[2], 0, 0)
metrics_stop = Time.utc(ARGV[3], ARGV[4], ARGV[5], 23, 59)

numRandomTopicsToPick = Integer(ARGV[6])
printf(STDERR, "numRandomTopicsToPick:%d", numRandomTopicsToPick)

db = Mongo::Connection.new.db("gs") # no error checking  :-) assume Get Satisfaction Database is there on localhost
topicsColl = db.collection("topics")

topics_array = []
topicsColl.find({"last_active_at" => {"$gte" => metrics_start, "$lte" => metrics_stop}
                }, :fields => ["at_sfn", "id"]).each do |t|
  url = t["at_sfn"]
  $stderr.printf("topic:%d, url:%s\n", t["id"],url)
  topics_array << url
end
random_topics=[]
for i in 1..numRandomTopicsToPick do
  while true do
    index = rand(topics_array.length)
    if topics_array[index] != nil
      random_topics[i] = topics_array[index]
      topics_array[index] = nil
      break
    end
  end
end

executable_name = $0.gsub(".rb","") 
printf(STDERR, "CSV filename:%s.%s%s%s.%s%s%s.csv",executable_name,ARGV[0],ARGV[1],ARGV[2],ARGV[3],ARGV[4],ARGV[5])
 
csv_file = File.new(executable_name+"."+ARGV[0]+ARGV[1]+ARGV[2]+"."+ARGV[3]+ARGV[4]+ARGV[5] + ".csv", "w")

random_topics.each{|topic_url|
  csv_file.puts "#{topic_url}"
}
 
csv_file.close